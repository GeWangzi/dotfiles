// YouTube Ad Speed Skipper
//
// While an ad is playing: mute it, run it at AD_RATE, and click the skip
// button as soon as one appears. When the ad ends, put the playback rate and
// mute state back exactly as they were, so a separate video-speed extension
// keeps whatever rate it had set on the real video.
//
// Running totals are kept in extension storage and shown by the popup.
//
// Diagnostics are on by default while the skip path is being tuned. Each ad
// logs whether a skip button ever appeared, how many clicks were sent, and
// whether playback stalled at speed. Silence it from the YouTube console with:
//   localStorage.ytAdSkipDebug = "0"

// Chrome refuses rates above 16 and audio is dropped well below that anyway.
const AD_RATE = 16;

// Feeding 16x needs 16x the bandwidth. When the network cannot keep up the ad
// stalls and takes real time anyway, so back the rate off until it recovers.
const MIN_RATE = 2;
const STALL_MS = 1200;

// Last resort for an ad that stalls even at MIN_RATE: jump to the end. Off by
// default because seeking is the behaviour YouTube is most likely to police.
const SEEK_ON_STALL = false;

// Pressing a button mutates the DOM, which wakes the observer, which would
// press again. These bounds keep that from becoming a loop that starves the
// event loop and freezes the tab.
const TICK_MIN_MS = 100;
const PRESS_THROTTLE_MS = 300;
const MAX_PRESSES_PER_AD = 12;

// Seeking is what actually ends an ad here: this YouTube build ignores
// synthetic presses on a live "Skip" button. The button is still tried first,
// briefly, because a real skip is cleaner than a seek when it works.
const PRESSES_BEFORE_SEEK = 2;

// Seek this long after an ad starts even if no skip button ever appears, which
// is what ends non-skippable ads. Long enough for the media to become
// seekable, short enough that the ad barely registers.
const SEEK_AFTER_MS = 800;
const SEEK_RETRY_MS = 500;
const MAX_SEEK_ATTEMPTS = 5;

// Land just short of the end rather than exactly on it. Parking the element
// on its final frame leaves the ad module waiting for a completion that never
// comes, which strands the player on the ad endcard -- a "Get app now" panel
// with a skip button that ignores presses like every other one. Playing the
// last fraction at speed fires the normal ended path instead.
const SEEK_MARGIN_S = 0.25;

// If an ad is showing but the media is parked, give it a nudge.
const STUCK_MS = 1500;
const STUCK_RETRY_MS = 2000;

// The "Skip in 5" widget. While it is up the skip control is inert, so
// presses are wasted and should not count toward the seek fallback.
const COUNTDOWN_SELECTORS = [
  ".ytp-ad-preview-container",
  ".ytp-ad-preview-text",
  ".ytp-ad-timed-pie-countdown-container",
];

const api = globalThis.browser ?? globalThis.chrome;
const STATS_KEY = "stats";

const DEBUG = (() => {
  try {
    return localStorage.getItem("ytAdSkipDebug") !== "0";
  } catch (err) {
    return true;
  }
})();

function log(...parts) {
  if (DEBUG) console.log("[ad-skip]", ...parts);
}

// Known skip controls, newest markup first.
const SKIP_SELECTORS = [
  ".ytp-skip-ad-button",
  ".ytp-ad-skip-button-modern",
  ".ytp-ad-skip-button",
  ".ytp-ad-skip-button-container",
  ".ytp-ad-overlay-close-button",
  ".ytp-ad-overlay-close-container",
];

// Overlay/banner ads that sit on top of the player and never "play".
const OVERLAY_SELECTORS = [
  ".ytp-ad-overlay-slot",
  ".ytp-ad-overlay-container",
  "#player-ads",
];

let saved = null;
let currentRate = AD_RATE;

// Per-ad measurement and diagnostics.
let adSource = null;
let adStartWall = 0;
let lastTime = 0;
let lastWall = 0;
let stalledSince = 0;
let sawSkipButton = false;
let clicksSent = 0;
let seekAttempts = 0;
let lastSeekWall = 0;
let adEndedBySeek = false;
let parkedSince = 0;
let lastNudgeWall = 0;
const pressedAt = new WeakMap();

let stats = { adsSkipped: 0, secondsSaved: 0 };
let statsLoaded = false;
let dirty = false;

async function loadStats() {
  try {
    const stored = await api.storage.local.get(STATS_KEY);
    if (stored && stored[STATS_KEY]) stats = { ...stats, ...stored[STATS_KEY] };
  } catch (err) {
    // Storage unavailable; keep counting in memory for this page only.
  }
  statsLoaded = true;
}

function flushStats() {
  if (!dirty || !statsLoaded) return;
  dirty = false;
  try {
    api.storage.local.set({ [STATS_KEY]: stats });
  } catch (err) {
    // A failed write only loses the delta since the last one.
  }
}

function getPlayer() {
  return document.querySelector(".html5-video-player");
}

function getVideo() {
  return document.querySelector("video.html5-main-video") ||
         document.querySelector(".html5-video-player video");
}

function adIsPlaying(player) {
  return player.classList.contains("ad-showing") ||
         player.classList.contains("ad-interrupting");
}

function setRate(video, rate) {
  try {
    video.playbackRate = rate;
    // YouTube reapplies defaultPlaybackRate on some source switches.
    video.defaultPlaybackRate = rate;
  } catch (err) {
    // Rate out of the browser's supported range; leave it alone.
  }
}

// offsetParent is null for anything inside a fixed-position ancestor, which
// the player uses in theater and fullscreen, so it cannot decide visibility.
function isVisible(element) {
  if (!element.getClientRects().length) return false;
  const style = getComputedStyle(element);
  return style.visibility !== "hidden" && style.display !== "none";
}

function countdownShowing(player) {
  for (const selector of COUNTDOWN_SELECTORS) {
    for (const element of player.querySelectorAll(selector)) {
      if (isVisible(element)) return element;
    }
  }
  return null;
}

function describe(element) {
  const text = (element.textContent || "").trim().replace(/\s+/g, " ").slice(0, 40);
  const disabled = element.disabled === true || element.getAttribute("aria-disabled") === "true";
  return `${element.className}${disabled ? " [disabled]" : ""} "${text}"`;
}

function findSkipButtons(player) {
  const found = new Set();
  for (const selector of SKIP_SELECTORS) {
    for (const element of player.querySelectorAll(selector)) {
      if (isVisible(element)) found.add(element);
    }
  }
  return [...found];
}

// A bare .click() misses handlers that listen for pointer events, so send the
// whole sequence a real press produces.
//
// The details matter more than the sequence does. PointerEventInit defaults
// pointerId to 0 and isPrimary to FALSE, so an event built from position alone
// describes a phantom secondary pointer with no button held, and any handler
// that sanity-checks isPrimary or button drops it on the floor.
function pressButton(element) {
  const rect = element.getBoundingClientRect();
  const x = rect.left + rect.width / 2;
  const y = rect.top + rect.height / 2;

  const base = {
    bubbles: true,
    cancelable: true,
    composed: true,
    view: window,
    detail: 1,
    button: 0,
    clientX: x,
    clientY: y,
    screenX: x,
    screenY: y,
  };
  const pointer = {
    ...base,
    pointerId: 1,
    pointerType: "mouse",
    isPrimary: true,
    width: 1,
    height: 1,
  };

  const sequence = [
    ["pointerover", PointerEvent, { ...pointer, buttons: 0, detail: 0 }],
    ["pointerenter", PointerEvent, { ...pointer, buttons: 0, detail: 0, bubbles: false }],
    ["mouseover", MouseEvent, { ...base, buttons: 0, detail: 0 }],
    ["pointermove", PointerEvent, { ...pointer, buttons: 0, detail: 0 }],
    ["mousemove", MouseEvent, { ...base, buttons: 0, detail: 0 }],
    ["pointerdown", PointerEvent, { ...pointer, buttons: 1, pressure: 0.5 }],
    ["mousedown", MouseEvent, { ...base, buttons: 1 }],
    ["pointerup", PointerEvent, { ...pointer, buttons: 0, pressure: 0 }],
    ["mouseup", MouseEvent, { ...base, buttons: 0 }],
    ["click", MouseEvent, { ...base, buttons: 0 }],
  ];

  try {
    element.focus({ preventScroll: true });
  } catch (err) {
    // Not focusable; the press below does not depend on it.
  }

  for (const [type, Ctor, init] of sequence) {
    try {
      element.dispatchEvent(new Ctor(type, init));
    } catch (err) {
      // Unsupported constructor for this type; keep going.
    }
  }

  try {
    element.click();
  } catch (err) {
    // Element vanished mid-press.
  }
}

// If the button refuses every press, end the ad by seeking instead. Ad media
// often reports duration NaN under MSE, so fall back to the seekable range.
function seekPastAd(video) {
  let end = NaN;
  if (Number.isFinite(video.duration) && video.duration > 0) {
    end = video.duration;
  } else if (video.seekable && video.seekable.length > 0) {
    end = video.seekable.end(video.seekable.length - 1);
  }
  if (!Number.isFinite(end) || end <= 0) return false;

  const target = end - SEEK_MARGIN_S;
  if (target <= video.currentTime + 0.1) return false;

  video.currentTime = target;
  resumeIfParked(video);
  return true;
}

// The ad has to keep playing for the seek to complete into the next item.
function resumeIfParked(video) {
  if (!video.paused) return;
  const played = video.play();
  if (played && typeof played.catch === "function") {
    played.catch(() => {
      // Autoplay refused; the watchdog will try again.
    });
  }
}

// Ends the ad by jumping to the end of its media. Runs once the button has
// had its chance, or once SEEK_AFTER_MS has passed with no usable button,
// which is the only thing that shortens a non-skippable ad.
function maybeSeek(video, player) {
  if (adEndedBySeek || seekAttempts >= MAX_SEEK_ATTEMPTS) return;

  const now = performance.now();
  const buttonExhausted = sawSkipButton && clicksSent >= PRESSES_BEFORE_SEEK;
  const waitedLongEnough = now - adStartWall > SEEK_AFTER_MS;
  if (!buttonExhausted && !waitedLongEnough) return;
  if (seekAttempts > 0 && now - lastSeekWall < SEEK_RETRY_MS) return;
  if (countdownShowing(player)) return;

  seekAttempts += 1;
  lastSeekWall = now;
  if (seekPastAd(video)) {
    adEndedBySeek = true;
    log(`seeking past the ad (attempt ${seekAttempts})`);
  } else if (seekAttempts >= MAX_SEEK_ATTEMPTS) {
    log("ad is not seekable; letting it run at speed");
  }
}

// Watchdog for an ad that is showing but not advancing: ended, or paused with
// no countdown running. That is the endcard state, and without this the tab
// sits there until the user clicks a button that does not respond.
function nudgeIfStuck(video, player) {
  const parked = video.ended || (video.paused && !countdownShowing(player));
  const now = performance.now();

  if (!parked) {
    parkedSince = 0;
    return;
  }
  if (parkedSince === 0) {
    parkedSince = now;
    return;
  }
  if (now - parkedSince < STUCK_MS) return;
  if (now - lastNudgeWall < STUCK_RETRY_MS) return;

  lastNudgeWall = now;
  log(`ad parked (ended=${video.ended} paused=${video.paused}); nudging`);

  // Give the button another budget: on an endcard it is the only control
  // present, and a press costs nothing if it is ignored again.
  clicksSent = 0;
  for (const button of findSkipButtons(player)) {
    pressedAt.delete(button);
  }
  resumeIfParked(video);
}

function clickSkipButtons(player, video) {
  if (clicksSent >= MAX_PRESSES_PER_AD) return;

  const buttons = findSkipButtons(player);
  if (buttons.length === 0) return;

  if (!sawSkipButton) {
    sawSkipButton = true;
    log("skip button appeared:", buttons.map(describe).join(" | "));
  }

  // Pressing during the countdown does nothing and must not spend the budget
  // that decides whether the button is hopeless.
  const countdown = countdownShowing(player);
  if (countdown) {
    log("countdown up, holding press:", describe(countdown));
    return;
  }

  const now = performance.now();
  for (const button of buttons) {
    // Retry a stubborn button, but never hammer one. Tracked per element:
    // a single shared timestamp lets several buttons take turns and defeat
    // the throttle entirely.
    const previous = pressedAt.get(button) ?? -Infinity;
    if (now - previous < PRESS_THROTTLE_MS) continue;
    pressedAt.set(button, now);
    clicksSent += 1;
    log(`press ${clicksSent}:`, describe(button));
    pressButton(button);
    if (clicksSent >= MAX_PRESSES_PER_AD) {
      log("press cap reached; leaving this ad alone");
      return;
    }
  }
}

function removeOverlays() {
  for (const selector of OVERLAY_SELECTORS) {
    for (const element of document.querySelectorAll(selector)) {
      element.remove();
    }
  }
}

function startAd(video) {
  adSource = video.currentSrc || video.src || "";
  adStartWall = performance.now();
  lastTime = video.currentTime;
  lastWall = performance.now();
  stalledSince = 0;
  sawSkipButton = false;
  clicksSent = 0;
  seekAttempts = 0;
  lastSeekWall = 0;
  adEndedBySeek = false;
  parkedSince = 0;
  lastNudgeWall = 0;
  currentRate = AD_RATE;
  stats.adsSkipped += 1;
  dirty = true;
  log("ad started, duration", video.duration);
}

function endAd(reason) {
  const wall = ((performance.now() - adStartWall) / 1000).toFixed(1);
  log(
    `ad ended (${reason}) after ${wall}s real time:`,
    `skip button ${sawSkipButton ? "seen" : "never appeared"},`,
    `${clicksSent} presses sent,`,
    adEndedBySeek ? "ended by seek," : "ended on its own,",
    `final rate ${currentRate}`
  );
}

// Counts each ad once, tracks the time the speed-up saves, and backs the rate
// off whenever playback stops advancing.
function measure(video) {
  const source = video.currentSrc || video.src || "";
  const now = performance.now();

  if (source !== adSource || video.currentTime + 2 < lastTime) {
    if (adSource !== null) endAd("next ad in break");
    startAd(video);
    return;
  }

  const contentSeconds = video.currentTime - lastTime;
  const wallSeconds = (now - lastWall) / 1000;
  lastTime = video.currentTime;
  lastWall = now;

  if (contentSeconds > wallSeconds) {
    stats.secondsSaved += contentSeconds - wallSeconds;
    dirty = true;
  }

  // readyState below HAVE_FUTURE_DATA means the buffer ran dry.
  const starved = contentSeconds <= 0 && !video.paused && video.readyState < 3;
  if (!starved) {
    stalledSince = 0;
    if (currentRate < AD_RATE) {
      currentRate = AD_RATE;
      setRate(video, currentRate);
      log("buffer recovered, back to", currentRate);
    }
    return;
  }

  if (stalledSince === 0) {
    stalledSince = now;
    return;
  }
  if (now - stalledSince < STALL_MS) return;

  stalledSince = now;
  if (currentRate > MIN_RATE) {
    currentRate = Math.max(MIN_RATE, currentRate / 2);
    setRate(video, currentRate);
    log("stalled at speed, backing off to", currentRate);
  } else if (SEEK_ON_STALL && Number.isFinite(video.duration) && video.duration > 0) {
    log("still stalled at min rate, seeking to end");
    video.currentTime = video.duration;
  } else {
    log("stalled at min rate; network cannot feed the ad any faster");
  }
}

function tick() {
  const player = getPlayer();
  const video = getVideo();
  if (!player || !video) return;

  if (adIsPlaying(player)) {
    if (saved === null) {
      // First tick of this ad: remember what the real video was doing.
      saved = { rate: video.playbackRate, muted: video.muted };
    }
    video.muted = true;
    // Re-assert every tick: YouTube and other speed extensions both reset it.
    if (video.playbackRate !== currentRate) setRate(video, currentRate);
    measure(video);
    nudgeIfStuck(video, player);
    clickSkipButtons(player, video);
    maybeSeek(video, player);
    return;
  }

  // Only sweep banner ads outside a video ad: deleting subtrees mid-break can
  // race the player's own ad UI render and cost us the skip button.
  removeOverlays();

  if (saved !== null) {
    endAd("break over");
    setRate(video, saved.rate);
    video.muted = saved.muted;
    saved = null;
    adSource = null;
    currentRate = AD_RATE;
    flushStats();
  }
}

// tick() mutates the DOM, so running it straight from the observer callback
// lets its own writes re-trigger it. Observer callbacks are microtasks, so
// that recursion never yields and the tab locks up. Everything goes through
// this scheduler instead: at most one pending run, at most one per
// TICK_MIN_MS, and always on a macrotask.
let tickPending = false;
let lastTickWall = 0;
let ticking = false;

function scheduleTick() {
  if (tickPending) return;
  tickPending = true;
  const wait = Math.max(0, TICK_MIN_MS - (performance.now() - lastTickWall));
  setTimeout(() => {
    tickPending = false;
    lastTickWall = performance.now();
    if (ticking) return;
    ticking = true;
    try {
      tick();
    } finally {
      ticking = false;
    }
  }, wait);
}

// Class changes on the player element are the reliable ad signal, so watch
// attributes as well as inserted nodes.
const observer = new MutationObserver(scheduleTick);
observer.observe(document.documentElement, {
  childList: true,
  subtree: true,
  attributes: true,
  attributeFilter: ["class"],
});

// Backstop: the observer misses transitions that happen without a DOM change,
// and the skip button becomes clickable purely on a timer.
setInterval(scheduleTick, 250);

// Write through during long breaks and when the tab goes away.
setInterval(flushStats, 5000);
window.addEventListener("pagehide", flushStats);

log("content script loaded on", location.pathname);
loadStats().then(scheduleTick);
