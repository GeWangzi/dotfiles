# YouTube Ad Speed Skipper

An unpacked Chrome/Firefox extension. While a YouTube ad plays it mutes the ad,
sets playback rate to 16x, presses the skip button if one appears, and seeks to
the end of the ad media shortly after. When the ad ends it restores the
playback rate and mute state that were in effect before, so a separate
video-speed extension is left undisturbed.

The seek is what does the work. Current YouTube ignores synthetic presses on
its skip button even when the button is live and reads "Skip", so the press is
attempted twice and then abandoned. Seeking also shortens non-skippable ads,
which no amount of clicking can touch. `SEEK_AFTER_MS` and
`PRESSES_BEFORE_SEEK` in `content.js` control the handover.

Clicking the toolbar icon opens a small popup with the number of ads skipped so
far and how much ad time the fast-forward has saved. Both totals are stored
locally by the extension and update live while the popup is open. The popup has
a Reset button.

## Install

1. Open `chrome://extensions` and turn on Developer mode.
2. Choose "Load unpacked" and select this directory
   (`~/.local/share/chrome-extensions/yt-ad-speedskip` once the `chrome` stow
   package is linked).
3. Reload any open YouTube tab.

Firefox: `about:debugging` -> This Firefox -> Load Temporary Add-on, and pick
`manifest.json`. From a terminal, `npx web-ext run` in this directory launches
Firefox with the extension already loaded. Installing permanently in release
Firefox requires a signed build: `npx web-ext sign --channel=unlisted`.

## Tuning

`AD_RATE` at the top of `content.js` is the ad playback rate. 16 is the highest
Chrome accepts. Lower it if ads stall waiting on the network at full speed.

## Limits

Ads are still downloaded and still count as viewed; only the wall-clock time
spent on them shrinks. Ads stitched server-side into the content stream cannot
be detected this way. The class names YouTube uses for the skip button change
every few months, so if skipping stops working, check the selectors in
`SKIP_SELECTORS` against the live player.

The counter treats a new media source, or playback jumping back to the start
mid-break, as a new ad. Back-to-back ads served over one reused media source
without a visible restart are counted once. The saved-time figure counts only
the surplus from playing fast, not the ad time avoided by pressing skip, so it
is a floor rather than the full saving.

## Diagnostics

Logging is on by default while the skip path is being tuned. Every line is
prefixed `[ad-skip]`, so filtering the console on that string hides YouTube's
own noise. Each ad logs whether a skip button ever appeared, how many clicks
were sent, and whether playback stalled at speed. Silence it with:

```js
localStorage.ytAdSkipDebug = "0"
```

The lines are `console.log`, so the console's level filter must include Info
for them to show.

An ad that takes real time despite the speed-up is usually starved rather than
unskipped: 16x needs 16x the bandwidth, and when the buffer runs dry the player
waits. The rate halves down to `MIN_RATE` while that lasts and returns to
`AD_RATE` once data flows again. `SEEK_ON_STALL` in `content.js` adds a
jump-to-end for an ad that stalls even at the floor; it is off by default.
