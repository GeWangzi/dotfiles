pragma Singleton

// The machine's vitals, read once here so every surface shows the same
// figures: battery, volume, wifi, brightness, do-not-disturb, thermals and
// memory, and the on-demand CPU/disk/GPU stats for the details menu.
//
// Everything here is event-driven or a cheap kernel-file read on a slow
// timer. No subprocess polling, no network probing.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire

Singleton {
    id: root

    // ---------------------------------------------------------------- battery

    readonly property var upower: UPower.displayDevice

    // Derived from the device's own state rather than UPower.onBattery: the
    // daemon-level flag read stale here (the bar said CHARGING while
    // draining), and state also distinguishes full/pending-charge on the
    // wire, which onBattery cannot.
    readonly property bool onBattery: upower && upower.ready
        ? upower.state === UPowerDeviceState.Discharging
          || upower.state === UPowerDeviceState.PendingDischarge
          || upower.state === UPowerDeviceState.Empty
        : UPower.onBattery
    readonly property bool charging: upower && upower.ready
        && upower.state === UPowerDeviceState.Charging

    // 0.0 - 1.0. UPowerDevice.percentage is already a fraction in quickshell.
    readonly property real battery: upower && upower.ready
        ? (upower.percentage > 1 ? upower.percentage / 100 : upower.percentage)
        : 1

    // "68% — 4H 10M" while draining, "82% — CHARGING" only while current is
    // actually flowing in, "100% — FULL" once it stops.
    readonly property string batteryText: {
        if (!upower || !upower.ready) return "";
        const pct = Math.round(root.battery * 100) + "%";
        if (root.charging) return pct + " — CHARGING";
        if (upower.state === UPowerDeviceState.FullyCharged) return pct + " — FULL";
        if (!root.onBattery) return pct;
        const s = upower.timeToEmpty;
        if (!s || s <= 0) return pct;
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        return pct + " — " + h + "H " + (m < 10 ? "0" : "") + m + "M";
    }

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

    // One handler for the whole singleton -- QML rejects a second
    // Component.onCompleted on the same object. syncProfile's rationale is
    // with the function, below.
    Component.onCompleted: {
        wifiQuery.running = true;
        syncProfile();
    }

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

    // The 0-8 step value. Set and read have to share one curve -- reading
    // back on a different curve made the meter lie, and clicking step 4 read
    // back as 0. That curve is plain linear over the raw value now, because
    // the kernel already supplies the perceptual one: amdgpu reports
    // /sys/class/backlight/amdgpu_bl1/scale as `non-linear`, meaning the raw
    // number is pre-mapped. brightnessctl -e4 stacked a second gamma on top
    // of it, which put the eight steps at 0.03/0.4/2/6/16/32/60/100 percent
    // of raw -- a 13x luminance jump from step 1 to step 2 and 1.7x from 7 to
    // 8, so the bottom of the dial did everything and the top did nothing.
    readonly property int bright8: Math.round(brightRaw / brightMax * 8)

    // No floor: step 0 is a genuinely dark panel (the user wants the bottom
    // bar to mean OFF). Recovery is the brightness-up key, which works
    // blind.
    function setBright8(n) {
        const step = Math.max(0, Math.min(8, n));
        Quickshell.execDetached(["brightnessctl", "set",
                                 "" + Math.round(step / 8 * brightMax)]);
    }

    // ---------------------------------------------------------------- do not disturb

    // The shell's own notification daemon owns do-not-disturb (swaync is
    // retired); this is its flag.
    readonly property bool dnd: Notifs.dnd

    // ---------------------------------------------------------------- memory and thermals

    // Kernel files on a slow clock: 30s cadence while idle, 5s while the
    // details menu is open (the stats timer below reloads the same files).
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

    // CPU, disk and GPU figures for the details menu. Only sampled while
    // the menu is open (`menuWants`); nothing here runs on a bare desktop.
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

    // The amdgpu sysfs node, resolved once at startup. cardN numbering is
    // not stable across boots (the NVIDIA card sometimes enumerates first;
    // .zprofile has the same problem with AQ_DRM_DEVICES), so the card is
    // taken from the stable by-path node of the iGPU's PCI address
    // (MACHINE.md hardware table), falling back to whichever card the amdgpu
    // driver claims. Empty when neither resolves: the GPU row then shows no
    // value at all rather than another card's number.
    property string gpuPath: ""

    Process {
        id: gpuResolve
        running: true
        command: ["sh", "-c",
            "c=$(readlink -e /dev/dri/by-path/pci-0000:04:00.0-card 2>/dev/null)\n"
            + "f=/sys/class/drm/${c##*/}/device/gpu_busy_percent\n"
            + "[ -n \"$c\" ] && [ -r \"$f\" ] && { echo \"$f\"; exit 0; }\n"
            + "for d in /sys/class/drm/card*/device/driver; do\n"
            + "  [ -e \"$d\" ] || continue\n"
            + "  case $(readlink \"$d\") in *amdgpu)\n"
            + "    f=${d%/driver}/gpu_busy_percent\n"
            + "    [ -r \"$f\" ] && { echo \"$f\"; exit 0; };;\n"
            + "  esac\n"
            + "done\n"
            + "exit 0"]
        stdout: StdioCollector {
            onStreamFinished: root.gpuPath = text.trim()
        }
    }

    FileView {
        id: gpuFile
        path: root.gpuPath
        printErrors: false
        onLoaded: root.gpuBusy = parseInt(text(), 10) || 0
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
            if (root.gpuPath !== "") gpuFile.reload();
            if (!dfQuery.running) dfQuery.running = true;
            if (!dfFull.running) dfFull.running = true;
        }
    }

    // The power profile follows the wire: unplugging drops to power saver,
    // plugging back in returns to balanced. power-profiles-daemon will not
    // do this on its own -- it holds whatever profile it was last handed --
    // and TLP used to, until it was removed on 2026-08-20 (MACHINE.md, "The
    // battery charge limit"). Without this the machine sat in balanced on
    // battery, which is the one thing TLP had still been doing for runtime.
    //
    // The wire always wins over a pick from the details menu, which is what
    // TLP did and keeps the rule sayable in one line: choose what you like,
    // but changing power source resets it.
    function syncProfile() {
        PowerProfiles.profile = root.onBattery
            ? PowerProfile.PowerSaver
            : PowerProfile.Balanced
    }

    // Both this signal AND the completion call (in the singleton's one
    // Component.onCompleted, up by the wifi query): on a boot that starts
    // on battery there is no transition to react to. UPower is often not
    // ready at completion, so the first call can read wrong -- the signal
    // corrects it a moment later.
    onOnBatteryChanged: syncProfile()

    // ---------------------------------------------------------------- uptime

    // /proc/uptime is read once at startup to pin the boot moment, and the
    // minute clock drives the figure from there -- no polling.
    property real bootEpochMs: 0

    FileView {
        path: "/proc/uptime"
        printErrors: false
        onLoaded: root.bootEpochMs = Date.now() - (parseFloat(text()) || 0) * 1000
    }

    readonly property real uptimeSec: bootEpochMs > 0
        ? Math.max(0, (clock.date.getTime() - bootEpochMs) / 1000)
        : 0

    // ---------------------------------------------------------------- clock

    readonly property var clock: SystemClock {
        precision: SystemClock.Minutes
    }

    readonly property string time: Qt.formatDateTime(clock.date, "HH:mm")
    readonly property string date: Qt.formatDateTime(clock.date, "ddd dd MMM").toUpperCase()
    readonly property bool night: clock.date.getHours() >= 19 || clock.date.getHours() < 7
}
