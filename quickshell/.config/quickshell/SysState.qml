pragma Singleton

// The machine's vitals, translated once into the creature vocabulary so every
// surface reads the same object:
//
//   battery      -> HP (there is no separate battery indicator anywhere)
//   power source -> held item (LEFTOVERS on charge, GANLON BERRY on battery)
//   volume       -> the trainable pair's audio half
//   wifi         -> the CONNECT move's link state
//   thermals     -> BRN status condition, and the THERMAL THROTTLE foe
//   memory       -> the MEM LEAK foe
//   do not disturb -> SUB, a field effect (dashed chip, never a filled one)
//
// Everything here is event-driven or a cheap kernel-file read on a slow
// timer. No subprocess polling, no network probing: the handoff's PAR chip
// (latency) was dropped for exactly that reason -- a chip that needs active
// probing is not worth the wakeups. SLP never renders while the machine is
// awake, which is the only time this shell is running.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire

Singleton {
    id: root

    // ---------------------------------------------------------------- HP

    readonly property var battery: UPower.displayDevice
    readonly property bool onBattery: UPower.onBattery

    // 0.0 - 1.0. UPowerDevice.percentage is already a fraction in quickshell.
    readonly property real hp: battery && battery.ready
        ? (battery.percentage > 1 ? battery.percentage / 100 : battery.percentage)
        : 1

    // "68% — 4H 10M" while draining, "82% — CHARGING" on the wire.
    readonly property string hpNum: {
        if (!battery || !battery.ready) return "";
        const pct = Math.round(root.hp * 100) + "%";
        if (!root.onBattery) return pct + " — CHARGING";
        const s = battery.timeToEmpty;
        if (!s || s <= 0) return pct;
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        return pct + " — " + h + "H " + (m < 10 ? "0" : "") + m + "M";
    }

    // The held item follows the power source and swaps itself (turn 20a).
    readonly property string heldItem: onBattery ? Skin.heldBattery : Skin.heldCharge
    readonly property string heldNote: onBattery
        ? "RAISES DEFENSE AT QUARTER HP — ON BATTERY"
        : "RESTORES A LITTLE HP EACH TURN — ON CHARGE"

    // ---------------------------------------------------------------- volume

    readonly property var sink: Pipewire.defaultAudioSink

    PwObjectTracker {
        objects: [root.sink]
    }

    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

    // Brightness keeps the design's 8 steps; volume shows 20 bars of 5%
    // each, matching what a keypress moves (user request).
    readonly property int vol8: muted ? 0 : Math.round(Math.min(1, volume) * 8)
    readonly property int vol20: muted ? 0 : Math.round(Math.min(1, volume) * 20)

    function setVolPct(pct) {
        if (!sink || !sink.audio) return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(100, pct)) / 100;
    }

    function setVol8(n) {
        if (!sink || !sink.audio) return;
        const v = Math.max(0, Math.min(8, n)) / 8;
        sink.audio.muted = false;
        sink.audio.volume = v;
    }

    // The keys move volume by 5 points, snapped to the 5% grid so repeated
    // presses land on round figures. The 8-block meters still show the
    // nearest bar; the readout shows the real percent.
    readonly property int volPct: muted ? 0 : Math.round(Math.min(1, volume) * 100)

    function nudgeVol(delta) {
        if (!sink || !sink.audio) return;
        const pct = Math.max(0, Math.min(100,
            Math.round((root.volPct + delta) / 5) * 5));
        sink.audio.muted = false;
        sink.audio.volume = pct / 100;
    }

    // ---------------------------------------------------------------- wifi

    // Kept simple and NetworkManager-event-driven: one long-lived
    // `nmcli monitor` subscription marks the state dirty, and one query runs
    // per change. Quickshell 0.3's Networking module could replace this, but
    // its WifiNetwork model is per-scan-result and this needs only three
    // facts: link up, SSID, rough signal.
    property bool wifiUp: false
    property string ssid: ""
    property int wifiBars: 0     // 0-4

    Process {
        id: wifiQuery
        command: ["nmcli", "-t", "-f", "ACTIVE,SIGNAL,SSID", "device", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                let up = false, name = "", bars = 0;
                for (let i = 0; i < lines.length; i++) {
                    const parts = lines[i].split(":");
                    if (parts[0] === "yes") {
                        up = true;
                        const signal = parseInt(parts[1], 10) || 0;
                        bars = Math.max(1, Math.ceil(signal / 25));
                        name = parts.slice(2).join(":");
                        break;
                    }
                }
                root.wifiUp = up;
                root.ssid = name;
                root.wifiBars = bars;
            }
        }
    }

    Process {
        id: wifiMonitor
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            // Any event at all re-runs the one-shot query. Debounced by the
            // fact that a Process that is already running ignores the set.
            onRead: wifiQuery.running = true
        }
    }

    Component.onCompleted: wifiQuery.running = true

    // ---------------------------------------------------------------- brightness

    // The backlight sysfs file changes whenever anything (keys, details
    // menu) adjusts it, and FileView's watchChanges makes that a push, not
    // a poll.
    property int brightRaw: 0
    property int brightMax: 1

    FileView {
        path: "/sys/class/backlight/amdgpu_bl1/max_brightness"
        printErrors: false
        onLoaded: root.brightMax = Math.max(1, parseInt(text(), 10) || 1)
    }

    FileView {
        id: brightFile
        path: "/sys/class/backlight/amdgpu_bl1/brightness"
        printErrors: false
        watchChanges: true
        onLoaded: root.brightRaw = parseInt(text(), 10) || 0
        onFileChanged: {
            reload();
            root.brightRaw = parseInt(text(), 10) || 0;
        }
    }

    // The 0-8 step value, on the SAME exponential curve brightnessctl -e4
    // uses for every write (keys and the details menu alike): percent p sets
    // raw = max * (p/100)^4, so reading back linearly made the meter lie --
    // clicking step 4 read back as 0 and low steps looked like they fell
    // below zero. Inverting the exponent makes set-then-read round-trip.
    readonly property int bright8: Math.round(Math.pow(brightRaw / brightMax, 1 / 4) * 8)

    // No floor: step 0 is a genuinely dark panel (the user wants the bottom
    // bar to mean OFF). Recovery is the brightness-up key, which works
    // blind.
    function setBright8(n) {
        const step = Math.max(0, Math.min(8, n));
        Quickshell.execDetached(["brightnessctl", "-e4", "set",
                                 Math.round(step / 8 * 100) + "%"]);
    }

    // ---------------------------------------------------------------- SUB (do not disturb)

    // swaync owns notifications for now; its -sw subscription emits a JSON
    // line on every state change, so this costs nothing between changes.
    property bool sub: false

    Process {
        command: ["swaync-client", "-sw"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    const state = JSON.parse(data);
                    if (state.dnd !== undefined) root.sub = !!state.dnd;
                } catch (e) { /* partial line; the next one will parse */ }
            }
        }
    }

    // ---------------------------------------------------------------- foes

    // The foe is whatever is eating the machine (data-driven, README table).
    // Two detectable ones, from kernel files on a slow clock:
    //
    //   MEM LEAK          available memory under 10%
    //   THERMAL THROTTLE  package temperature at or past 90C, which is also
    //                     what raises the BRN condition
    //
    // 30s cadence, plain file reads. This is the whole cost of the bar's
    // in-combat state.
    property int memTotalKb: 0
    property int memAvailKb: 0
    property int tempC: 0

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            const lines = text().split("\n");
            for (let i = 0; i < lines.length; i++) {
                if (lines[i].startsWith("MemTotal:"))
                    root.memTotalKb = parseInt(lines[i].replace(/\D+/g, ""), 10);
                else if (lines[i].startsWith("MemAvailable:")) {
                    root.memAvailKb = parseInt(lines[i].replace(/\D+/g, ""), 10);
                    break;
                }
            }
        }
    }

    FileView {
        id: thermal
        path: "/sys/class/thermal/thermal_zone0/temp"
        printErrors: false
        onLoaded: root.tempC = Math.round(parseInt(text(), 10) / 1000)
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            meminfo.reload();
            thermal.reload();
        }
    }

    readonly property real memFreeFraction: memTotalKb > 0 ? memAvailKb / memTotalKb : 1

    // ---------------------------------------------------------------- stats on demand

    // CPU and disk figures for the details menu. Only sampled while the
    // menu is open (`menuWants`). The wallpaper's stat rows were removed at
    // the user's request (2026-08-19), so nothing here runs on a bare
    // desktop any more.
    property bool menuWants: false
    readonly property bool statsWanted: menuWants

    property real cpuPct: 0
    property string diskFree: ""

    property var cpuPrev: null

    FileView {
        id: procStat
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            const first = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const total = first.reduce((a, b) => a + b, 0);
            const idle = first[3] + (first[4] || 0);
            if (root.cpuPrev) {
                const dt = total - root.cpuPrev.total;
                const di = idle - root.cpuPrev.idle;
                if (dt > 0) root.cpuPct = Math.max(0, Math.min(1, 1 - di / dt));
            }
            root.cpuPrev = { total: total, idle: idle };
        }
    }

    Process {
        id: dfQuery
        command: ["df", "--output=avail", "-BG", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const g = parseInt(lines[lines.length - 1], 10);
                if (!isNaN(g)) root.diskFree = g + "G FREE";
            }
        }
    }

    property int diskSizeG: 0
    property int diskAvailG: 0

    Process {
        id: dfFull
        command: ["df", "--output=size,avail", "-BG", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const parts = lines[lines.length - 1].trim().split(/\s+/);
                const size = parseInt(parts[0], 10);
                const avail = parseInt(parts[1], 10);
                if (!isNaN(size)) root.diskSizeG = size;
                if (!isNaN(avail)) {
                    root.diskAvailG = avail;
                    root.diskFree = avail + "G FREE";
                }
            }
        }
    }

    property int cpuCurMHz: 0
    property int cpuMaxMHz: 1

    FileView {
        id: cpuMaxFile
        path: "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"
        printErrors: false
        onLoaded: root.cpuMaxMHz = Math.max(1, Math.round(parseInt(text(), 10) / 1000))
    }

    FileView {
        id: cpuCurFile
        path: "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
        printErrors: false
        onLoaded: root.cpuCurMHz = Math.round(parseInt(text(), 10) / 1000)
    }

    property int gpuBusy: 0

    FileView {
        id: gpuFile
        path: "/sys/class/drm/card1/device/gpu_busy_percent"
        printErrors: false
        onLoaded: root.gpuBusy = parseInt(text(), 10) || 0
    }

    property int cores: 0

    Process {
        command: ["nproc"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.cores = parseInt(text.trim(), 10) || 0
        }
    }

    Timer {
        running: root.statsWanted
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            procStat.reload();
            meminfo.reload();
            thermal.reload();
            cpuCurFile.reload();
            gpuFile.reload();
            if (!dfQuery.running) dfQuery.running = true;
            if (!dfFull.running) dfFull.running = true;
        }
    }

    // The IVs: hardware, fixed at birth, they cap the stats.
    readonly property var ivRows: [
        { label: "RAM", val: Math.round(memTotalKb / 1024 / 1024) + " GB", note: "CAPS SPEED" },
        { label: "CORES", val: String(cores), note: "CAPS ATTACK" },
        { label: "DISK", val: diskSizeG + " GB", note: "CAPS SP. DEF" }
    ]

    // The six stats of the details menu's STATS section, each mapped to the
    // real figure named in its sub-label.
    readonly property var statRows: [
        { label: "HP", sub: "BATTERY", val: hpNum,
          frac: hp, hue: Skin.hpColor(hp) },
        { label: "ATTACK", sub: "CPU CLOCK",
          val: (cpuCurMHz / 1000).toFixed(1) + " / " + (cpuMaxMHz / 1000).toFixed(1) + " GHZ",
          frac: cpuCurMHz / cpuMaxMHz, hue: Skin.cmd },
        { label: "DEFENSE", sub: "THERMALS",
          val: tempC + "°C — " + Math.max(0, 90 - tempC) + " HEADROOM",
          frac: Math.max(0, Math.min(1, 1 - tempC / 90)), hue: Skin.net },
        { label: "SP. ATK", sub: "GPU LOAD", val: gpuBusy + "%",
          frac: gpuBusy / 100, hue: Skin.snd },
        { label: "SP. DEF", sub: "DISK FREE",
          val: diskAvailG + " / " + diskSizeG + " GB",
          frac: diskSizeG > 0 ? diskAvailG / diskSizeG : 0, hue: Skin.txt },
        { label: "SPEED", sub: "MEMORY FREE",
          val: (memAvailKb / 1024 / 1024).toFixed(1) + " / "
               + Math.round(memTotalKb / 1024 / 1024) + " GB",
          frac: memFreeFraction, hue: Skin.ok }
    ]

    readonly property bool brn: tempC >= 90

    // Null when nothing is attacking, which is almost always.
    readonly property var foe: {
        if (root.memFreeFraction < 0.10 && root.memTotalKb > 0)
            return { name: "MEM LEAK", level: 62,
                     hp: Math.max(0.05, root.memFreeFraction * 10),
                     log: "MEM LEAK is still growing!" };
        if (root.brn)
            return { name: "THERMAL THROTTLE", level: 48,
                     hp: Math.max(0.05, Math.min(1, (105 - root.tempC) / 30)),
                     log: "THERMAL THROTTLE turned up the heat!" };
        return null;
    }

    // Status chips, already filtered to what is real. Filled chips only;
    // SUB is a field effect and surfaces render it dashed, separately.
    readonly property var chips: {
        const out = [];
        if (root.brn) out.push({ label: "BRN", hue: Skin.brn });
        return out;
    }

    // ---------------------------------------------------------------- EXP (uptime)

    // EXP is time awake, at the user's request (2026-08-19): /proc/uptime is
    // read once at startup to pin the boot moment, and the minute clock
    // drives the bar from there -- no polling. The bar wraps every 24 hours
    // of uptime, so a full sliver is a day without a reboot.
    property real bootEpochMs: 0

    FileView {
        path: "/proc/uptime"
        printErrors: false
        onLoaded: root.bootEpochMs = Date.now() - (parseFloat(text()) || 0) * 1000
    }

    readonly property real uptimeSec: bootEpochMs > 0
        ? Math.max(0, (clock.date.getTime() - bootEpochMs) / 1000)
        : 0
    readonly property real expFrac: (uptimeSec % 86400) / 86400

    // ---------------------------------------------------------------- clock

    readonly property var clock: SystemClock {
        precision: SystemClock.Minutes
    }

    readonly property string time: Qt.formatDateTime(clock.date, "HH:mm")
    readonly property string date: Qt.formatDateTime(clock.date, "ddd dd MMM").toUpperCase()
    readonly property bool night: clock.date.getHours() >= 19 || clock.date.getHours() < 7
}
