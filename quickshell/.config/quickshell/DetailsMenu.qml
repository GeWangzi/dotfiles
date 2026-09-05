// The details menu, control-deck form (2026-08-24 redesign): ONE screen,
// no sections, no drill-in. Three panels -- NETWORK, AUDIO, POWER -- over a
// vitals band and a key-hint footer. Every row is either a control (return
// applies it) or a diagnostic; nothing here is decoration. The old
// section-based game menu survives whole as GameMenu.qml, and the skin's
// `menu` variant picks between them (shell.qml) -- the creature costume
// keeps its SUMMARY/STATS/... dress, the plain shell gets this deck.
//
// Keys: tab or left/right moves between panels, up/down between rows,
// return applies, ESC closes. Focus is a (panel, row) pair; each panel
// counts its own rows, dynamic lists (saved networks, bluetooth devices,
// sinks) included.
//
// Everything shown is real: wifi is NetworkManager, bluetooth is bluez,
// audio is Pipewire, media is MPRIS, power is UPower and
// power-profiles-daemon, the proxy row is the sing-box unit. The saved
// networks list shows only profiles NetworkManager already knows -- return
// connects without a password prompt, which is why unknown networks are not
// listed (joining one needs a password flow; that is SUPER+C nmtui's job).
//
// Root actions (proxy toggle) dismiss the menu before exec: polkit's auth
// dialog cannot stack above the Overlay layer, so it would open invisibly
// behind this surface. Same trap as the timezone note in GameMenu.qml.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Bluetooth

PanelWindow {
    id: win

    signal dismissed()

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "rpg-details"

    // ---------------------------------------------------------------- focus

    // (panel, row). Panels: 0 NETWORK, 1 AUDIO, 2 POWER. Rows are counted
    // per panel below; the vitals band and footer take no focus.
    property int pIdx: 0
    property int rIdx: 0

    function foc(p, r) { return pIdx === p && rIdx === r; }

    readonly property int rowCount: {
        switch (pIdx) {
        case 0: return 1 + savedNearby.length + 1 + btDevices.length + 1;
        case 1: return sinkList.length + 3;
        default: return 5;
        }
    }

    onVisibleChanged: {
        SysState.menuWants = visible;
        if (visible) {
            pIdx = 0;
            rIdx = 0;
            keys.forceActiveFocus();
            refresh();
        }
    }

    function refresh() {
        if (!wifiDetail.running) wifiDetail.running = true;
        if (!nearbyScan.running) nearbyScan.running = true;
        if (!proxyQuery.running) proxyQuery.running = true;
        if (!warmQuery.running) warmQuery.running = true;
        if (!limitQuery.running) limitQuery.running = true;
        if (!tzQuery.running) tzQuery.running = true;
    }

    Timer {
        running: win.visible
        interval: 5000
        repeat: true
        onTriggered: win.refresh()
    }

    // ---------------------------------------------------------------- network data

    property string wifiIp: "—"

    Process {
        id: wifiDetail
        command: ["sh", "-c",
            "nmcli -t -g IP4.ADDRESS device show 2>/dev/null | grep -m1 ."]
        stdout: StdioCollector {
            onStreamFinished: win.wifiIp = text.trim() !== ""
                ? text.trim().split("/")[0] : "—"
        }
    }

    // Saved profiles that are in range right now. Two nmcli calls behind one
    // marker line; the intersection happens here because nmcli cannot join
    // them itself.
    property var savedNearby: []

    Process {
        id: nearbyScan
        command: ["sh", "-c",
            "nmcli -t -f NAME,TYPE connection show; echo ---; " +
            "nmcli -t -f SSID,SIGNAL dev wifi list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const halves = text.split("---\n");
                if (halves.length < 2) { win.savedNearby = []; return; }
                const saved = new Set();
                halves[0].trim().split("\n").forEach(line => {
                    const i = line.lastIndexOf(":");
                    if (i > 0 && line.slice(i + 1).includes("wireless"))
                        saved.add(line.slice(0, i).replace(/\\:/g, ":"));
                });
                const best = {};
                halves[1].trim().split("\n").forEach(line => {
                    const i = line.lastIndexOf(":");
                    if (i <= 0) return;
                    const ssid = line.slice(0, i).replace(/\\:/g, ":");
                    const sig = parseInt(line.slice(i + 1), 10) || 0;
                    if (ssid === "" || ssid === SysState.ssid) return;
                    if (!saved.has(ssid)) return;
                    if (!best[ssid] || best[ssid] < sig) best[ssid] = sig;
                });
                win.savedNearby = Object.keys(best)
                    .map(name => ({ name: name, sig: best[name] }))
                    .sort((a, b) => b.sig - a.sig)
                    .slice(0, 3);
            }
        }
    }

    // Proxy: the sing-box unit. is-active needs no privilege; the toggle
    // goes through polkit (see the header note about the dialog).
    property bool proxyOn: false

    Process {
        id: proxyQuery
        command: ["systemctl", "is-active", "sing-box"]
        stdout: StdioCollector {
            onStreamFinished: win.proxyOn = text.trim() === "active"
        }
    }

    function toggleProxy() {
        const cmd = win.proxyOn ? "stop" : "start";
        win.dismissed();
        Quickshell.execDetached(["systemctl", cmd, "sing-box"]);
    }

    // Bluetooth. Paired devices, connected first, capped so the panel
    // cannot overflow.
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btDevices: {
        const out = [];
        const devs = Bluetooth.devices.values;
        for (let i = 0; i < devs.length; i++)
            if (devs[i].paired || devs[i].connected) out.push(devs[i]);
        out.sort((a, b) => (b.connected ? 1 : 0) - (a.connected ? 1 : 0));
        return out.slice(0, 3);
    }

    // ---------------------------------------------------------------- audio data

    readonly property var sinkList: {
        const out = [];
        const nodes = Pipewire.nodes.values;
        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i];
            if (n.isSink && !n.isStream) out.push(n);
        }
        return out.slice(0, 3);
    }

    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool micMuted: source && source.audio
        ? source.audio.muted : false

    readonly property var player: {
        const players = Mpris.players.values;
        for (let i = 0; i < players.length; i++)
            if (players[i].playbackState === MprisPlaybackState.Playing)
                return players[i];
        return players.length > 0 ? players[0] : null;
    }

    // ---------------------------------------------------------------- power data

    readonly property var battery: UPower.displayDevice

    readonly property string batterySub: {
        if (!battery || !battery.ready) return "";
        const limit = win.chargeLimit > 0 ? " · LIMIT " + win.chargeLimit + "%" : "";
        if (SysState.charging) {
            const s = battery.timeToFull;
            if (s && s > 0)
                return Math.floor(s / 3600) + ":"
                    + (Math.floor((s % 3600) / 60) < 10 ? "0" : "")
                    + Math.floor((s % 3600) / 60) + " TO FULL" + limit;
            return "CHARGING" + limit;
        }
        if (!SysState.onBattery) return "PLUGGED IN" + limit;
        const s = battery.timeToEmpty;
        if (s && s > 0)
            return Math.floor(s / 3600) + ":"
                + (Math.floor((s % 3600) / 60) < 10 ? "0" : "")
                + Math.floor((s % 3600) / 60) + " LEFT" + limit;
        return "ON BATTERY" + limit;
    }

    property int chargeLimit: 0

    Process {
        id: limitQuery
        command: ["sh", "-c",
            "cat /sys/class/power_supply/BAT*/charge_control_end_threshold 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: win.chargeLimit = parseInt(text.trim(), 10) || 0
        }
    }

    readonly property var perfModes: [
        { label: "QUIET",    profile: PowerProfile.PowerSaver },
        { label: "BALANCED", profile: PowerProfile.Balanced },
        { label: "PERF",     profile: PowerProfile.Performance }
    ]

    function cyclePerf() {
        const cur = PowerProfiles.profile;
        for (let i = 0; i < perfModes.length; i++) {
            if (perfModes[i].profile === cur) {
                PowerProfiles.profile
                    = perfModes[(i + 1) % perfModes.length].profile;
                return;
            }
        }
        PowerProfiles.profile = PowerProfile.Balanced;
    }

    // Night light. Same round-trippable query/toggle as SUPER+SHIFT+N in
    // hyprland.lua -- identity would latch (see the comment there), so the
    // off state is temperature 6000.
    property bool warm: false

    Process {
        id: warmQuery
        command: ["hyprctl", "hyprsunset", "temperature"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = parseInt(text.trim(), 10);
                if (t > 0) win.warm = t < 5000;
            }
        }
    }

    function toggleWarm() {
        Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature",
                                 win.warm ? "6000" : "4000"]);
        win.warm = !win.warm;
    }

    // Timezone ring, unchanged from the game menu (and the same polkit
    // caveat: without the 49-rpg-shell rule the auth dialog opens behind
    // this surface).
    readonly property var timezones: ["Asia/Shanghai", "Asia/Tokyo", "UTC",
                                      "Europe/London", "America/New_York",
                                      "America/Chicago", "America/Los_Angeles"]
    property string timezone: ""

    Process {
        id: tzQuery
        command: ["timedatectl", "show", "-p", "Timezone", "--value"]
        stdout: StdioCollector {
            onStreamFinished: win.timezone = text.trim()
        }
    }

    function cycleTimezone() {
        const i = timezones.indexOf(timezone);
        const zone = timezones[(i + 1) % timezones.length];
        Quickshell.execDetached(["timedatectl", "set-timezone", zone]);
        win.timezone = zone;
    }

    // Spelled H/M rather than a colon: the titlebar already ends in the
    // clock, and a second colon-time ("UP 3:12") reads as another clock.
    readonly property string uptimeStr: {
        const s = SysState.uptimeSec;
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        return h > 0 ? h + "H " + m + "M" : m + "M";
    }

    // ---------------------------------------------------------------- apply

    function apply() {
        const r = rIdx;
        if (pIdx === 0) {
            const nSaved = savedNearby.length;
            if (r === 0) {
                Quickshell.execDetached(["nmcli", "radio", "wifi",
                                         SysState.wifiUp ? "off" : "on"]);
            } else if (r <= nSaved) {
                Quickshell.execDetached(["nmcli", "con", "up", "id",
                                         savedNearby[r - 1].name]);
            } else if (r === nSaved + 1) {
                if (btAdapter) btAdapter.enabled = !btAdapter.enabled;
            } else if (r <= nSaved + 1 + btDevices.length) {
                const dev = btDevices[r - nSaved - 2];
                dev.connected = !dev.connected;
            } else {
                toggleProxy();
            }
        } else if (pIdx === 1) {
            const nSinks = sinkList.length;
            if (r < nSinks) {
                Pipewire.preferredDefaultAudioSink = sinkList[r];
            } else if (r === nSinks) {
                SysState.setVolPct(SysState.volPct >= 100 ? 0 : SysState.volPct + 5);
            } else if (r === nSinks + 1) {
                if (source && source.audio) source.audio.muted = !source.audio.muted;
            } else {
                if (player) player.togglePlaying();
            }
        } else {
            switch (r) {
            case 0: cyclePerf(); break;
            case 1: SysState.setBright8((SysState.bright8 % 8) + 1); break;
            case 2: toggleWarm(); break;
            case 3: Notifs.toggleDnd(); break;
            case 4: cycleTimezone(); break;
            }
        }
    }

    // Mouse path: focus the row, then apply -- one tap does both, and the
    // gold border follows the pointer the same way it follows the keys.
    function tapRow(p, r) {
        pIdx = p;
        rIdx = r;
        apply();
    }

    // ---------------------------------------------------------------- input

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        TapHandler {
            onTapped: eventPoint => {
                const p = deck.mapFromItem(keys,
                    eventPoint.position.x, eventPoint.position.y);
                if (p.x < 0 || p.y < 0 || p.x > deck.width || p.y > deck.height)
                    win.dismissed();
            }
        }

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Tab:
            case Qt.Key_Right:
                win.pIdx = (win.pIdx + 1) % 3;
                win.rIdx = 0;
                break;
            case Qt.Key_Backtab:
            case Qt.Key_Left:
                win.pIdx = (win.pIdx + 2) % 3;
                win.rIdx = 0;
                break;
            case Qt.Key_Up:
                win.rIdx = Math.max(0, win.rIdx - 1);
                break;
            case Qt.Key_Down:
                win.rIdx = Math.min(win.rowCount - 1, win.rIdx + 1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                win.apply();
                break;
            case Qt.Key_Escape:
                win.dismissed();
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        // ------------------------------------------------------------ frame

        SoftShadow {
            x: deck.x
            y: deck.y
            width: deck.width
            height: deck.height
            offsetY: 10
        }

        Rectangle {
            id: deck
            width: 1060
            height: 620
            anchors.centerIn: parent
            color: Skin.bg
            border.width: 2
            border.color: Skin.inner
            radius: Skin.radius

            // Titlebar: name left, uptime and clock right.
            Rectangle {
                id: strip
                x: 2
                y: 2
                width: parent.width - 4
                height: 32
                color: Skin.cell

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 2
                    color: Skin.inner
                }

                Text {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: Skin.lex("details_title", "SYSTEM")
                    color: Skin.text
                    font.family: Skin.fontLabel
                    font.bold: true
                    font.pixelSize: 12
                    font.letterSpacing: 12 * 0.10
                }

                // Uptime sits apart on the left of the group; date and time
                // sit together as one datetime read, the clock bold at the
                // end. Only the clock carries a colon.
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 24

                    Text {
                        text: "UP " + win.uptimeStr
                        color: Skin.dim
                        font.family: Skin.fontLabel
                        font.pixelSize: 11
                        font.letterSpacing: 11 * 0.10
                    }

                    Row {
                        spacing: 8

                        Text {
                            text: SysState.date
                            color: Skin.body
                            font.family: Skin.fontLabel
                            font.pixelSize: 11
                            font.letterSpacing: 11 * 0.10
                        }

                        Text {
                            text: SysState.time
                            color: Skin.text
                            font.family: Skin.fontLabel
                            font.bold: true
                            font.pixelSize: 11
                            font.letterSpacing: 11 * 0.10
                        }
                    }
                }
            }

            // ------------------------------------------------------ panels

            Row {
                id: panels
                x: 16
                y: strip.y + strip.height + 14
                spacing: 12

                readonly property int colW: (deck.width - 32 - 24) / 3
                readonly property int colH: deck.height - strip.height - 2
                                            - 28 - vitals.height - 12
                                            - footer.height - 12

                // ---------------------------------------- NETWORK
                Panel {
                    width: panels.colW
                    height: panels.colH
                    title: "NETWORK"
                    chipText: SysState.wifiUp ? "WIFI ON" : "WIFI OFF"
                    chipColor: SysState.wifiUp ? Skin.cmd : Skin.dim
                    onChipTapped: win.tapRow(0, 0)

                    Column {
                        width: parent.width

                        // Current network; return toggles the radio.
                        FocusRow {
                            width: parent.width
                            height: 52
                            active: win.foc(0, 0)
                            onTapped: win.tapRow(0, 0)

                            Column {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3

                                Row {
                                    spacing: 8

                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "wifi"
                                        size: 14
                                        color: SysState.wifiUp ? Skin.body : Skin.critical
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: SysState.wifiUp
                                            ? SysState.ssid.toUpperCase() : "NO LINK"
                                        color: SysState.wifiUp ? Skin.text : Skin.critical
                                        font.family: Skin.fontLabel
                                        font.bold: true
                                        font.pixelSize: 12
                                    }
                                }

                                Text {
                                    text: win.wifiIp
                                    color: Skin.dim
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 10
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: SysState.wifiUp ? (SysState.wifiBars * 25) + "%" : ""
                                color: Skin.dim
                                font.family: Skin.fontLabel
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Skin.inner }

                        SubLabel { text: "SAVED NEARBY · ⏎ CONNECTS" }

                        Repeater {
                            model: win.savedNearby

                            FocusRow {
                                required property var modelData
                                required property int index

                                width: parent.width
                                height: 26
                                active: win.foc(0, 1 + index)
                                onTapped: win.tapRow(0, 1 + index)

                                Text {
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.modelData.name.toUpperCase()
                                    color: Skin.body
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 11
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.modelData.sig + "%"
                                    color: Skin.dim
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 10
                                }
                            }
                        }

                        Text {
                            visible: win.savedNearby.length === 0
                            x: 12
                            topPadding: 4
                            bottomPadding: 6
                            text: "NONE IN RANGE"
                            color: Skin.dim
                            font.family: Skin.fontLabel
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.12
                        }

                        // Bluetooth: the strip row is the adapter toggle.
                        FocusRow {
                            width: parent.width
                            height: 26
                            active: win.foc(0, 1 + win.savedNearby.length)
                            baseColor: Skin.cell
                            onTapped: win.tapRow(0, 1 + win.savedNearby.length)

                            Text {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: "BLUETOOTH"
                                color: Skin.text
                                font.family: Skin.fontLabel
                                font.bold: true
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: win.btAdapter && win.btAdapter.enabled ? "ON" : "OFF"
                                color: win.btAdapter && win.btAdapter.enabled
                                    ? Skin.cmd : Skin.dim
                                font.family: Skin.fontLabel
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }
                        }

                        Repeater {
                            model: win.btDevices

                            FocusRow {
                                required property var modelData
                                required property int index

                                width: parent.width
                                height: 28
                                active: win.foc(0, 2 + win.savedNearby.length + index)
                                onTapped: win.tapRow(0, 2 + win.savedNearby.length + index)

                                Row {
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8

                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "bt"
                                        size: 12
                                        color: parent.parent.modelData.connected
                                            ? Skin.body : Skin.dim
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (parent.parent.modelData.name || "?").toUpperCase()
                                        color: parent.parent.modelData.connected
                                            ? Skin.text : Skin.body
                                        font.family: Skin.fontLabel
                                        font.bold: parent.parent.modelData.connected
                                        font.pixelSize: 11
                                    }
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.modelData.connected
                                        ? (parent.modelData.batteryAvailable
                                           ? Math.round(parent.modelData.battery * 100) + "% · CONN"
                                           : "CONN")
                                        : "PAIRED"
                                    color: parent.modelData.connected ? Skin.cmd : Skin.dim
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 10
                                    font.letterSpacing: 10 * 0.10
                                }
                            }
                        }

                        // Proxy pins to the panel's bottom edge via the
                        // spacer math below being unnecessary -- the column
                        // just runs on; the divider keeps it read as its
                        // own block.
                        Rectangle { width: parent.width; height: 1; color: Skin.inner }

                        FocusRow {
                            width: parent.width
                            height: 30
                            active: win.foc(0, 2 + win.savedNearby.length
                                               + win.btDevices.length)
                            onTapped: win.tapRow(0, 2 + win.savedNearby.length
                                                    + win.btDevices.length)

                            Row {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "globe"
                                    size: 13
                                    color: Skin.body
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "PROXY · SING-BOX"
                                    color: Skin.body
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 10
                                    font.letterSpacing: 10 * 0.12
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: win.proxyOn ? "ON" : "OFF"
                                color: win.proxyOn ? Skin.cmd : Skin.dim
                                font.family: Skin.fontLabel
                                font.bold: win.proxyOn
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }
                        }
                    }
                }

                // ---------------------------------------- AUDIO
                Panel {
                    width: panels.colW
                    height: panels.colH
                    title: "AUDIO"
                    chipText: win.micMuted ? "MIC MUTED" : "MIC LIVE"
                    chipColor: win.micMuted ? Skin.critical : Skin.cmd
                    onChipTapped: win.tapRow(1, win.sinkList.length + 1)

                    Column {
                        width: parent.width

                        SubLabel { text: "OUTPUT" }

                        Repeater {
                            model: win.sinkList

                            FocusRow {
                                required property var modelData
                                required property int index

                                readonly property bool isDefault:
                                    SysState.sink === modelData

                                width: parent.width
                                height: 28
                                active: win.foc(1, index)
                                onTapped: win.tapRow(1, index)

                                Text {
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 60
                                    elide: Text.ElideRight
                                    text: (parent.modelData.description
                                           || parent.modelData.name || "?").toUpperCase()
                                    color: parent.isDefault ? Skin.text : Skin.body
                                    font.family: Skin.fontLabel
                                    font.bold: parent.isDefault
                                    font.pixelSize: 11
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.isDefault ? "◀" : ""
                                    color: Skin.accent
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 10
                                }
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Skin.inner }

                        // Volume: return steps +5%, clicking a block sets it.
                        FocusRow {
                            width: parent.width
                            height: 38
                            active: win.foc(1, win.sinkList.length)
                            onTapped: win.tapRow(1, win.sinkList.length)

                            Row {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24
                                spacing: 10

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "vol"
                                    size: 15
                                    color: SysState.muted ? Skin.critical : Skin.body
                                }

                                StepMeter {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 15 - 10 - 34
                                    height: 12
                                    steps: 20
                                    value: SysState.vol20
                                    fillColor: Skin.accent
                                    onStepClicked: n => SysState.setVolPct(n * 5)
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24
                                    horizontalAlignment: Text.AlignRight
                                    text: SysState.muted ? "M" : SysState.volPct
                                    color: Skin.text
                                    font.family: Skin.fontLabel
                                    font.bold: true
                                    font.pixelSize: 12
                                }
                            }
                        }

                        // Mic mute.
                        FocusRow {
                            width: parent.width
                            height: 26
                            active: win.foc(1, win.sinkList.length + 1)
                            onTapped: win.tapRow(1, win.sinkList.length + 1)

                            Text {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: "MICROPHONE"
                                color: Skin.body
                                font.family: Skin.fontLabel
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: win.micMuted ? "MUTED" : "LIVE"
                                color: win.micMuted ? Skin.critical : Skin.cmd
                                font.family: Skin.fontLabel
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Skin.inner }

                        SubLabel {
                            text: win.player
                                ? (win.player.playbackState === MprisPlaybackState.Playing
                                   ? "PLAYING" : "PAUSED")
                                  + (win.player.identity
                                     ? " · " + win.player.identity.toUpperCase() : "")
                                : "NO PLAYER"
                        }

                        // Now playing; return (or tap) toggles play/pause.
                        FocusRow {
                            width: parent.width
                            height: 54
                            active: win.foc(1, win.sinkList.length + 2)
                            onTapped: win.tapRow(1, win.sinkList.length + 2)

                            Column {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 56
                                spacing: 3

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: win.player && win.player.trackTitle
                                        ? win.player.trackTitle : "—"
                                    color: Skin.text
                                    font.family: Skin.fontLabel
                                    font.bold: true
                                    font.pixelSize: 12
                                }

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: win.player && win.player.trackArtist
                                        ? win.player.trackArtist : ""
                                    color: Skin.dim
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 10
                                }
                            }

                            // Play/pause state glyph, drawn not typed.
                            Item {
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12
                                height: 14

                                readonly property bool playing: win.player
                                    && win.player.playbackState === MprisPlaybackState.Playing

                                Row {
                                    visible: parent.playing
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Rectangle { width: 3; height: 14; color: Skin.text }
                                    Rectangle { width: 3; height: 14; color: Skin.text }
                                }

                                Canvas {
                                    visible: !parent.playing
                                    anchors.fill: parent
                                    onPaint: {
                                        const c = getContext("2d");
                                        c.reset();
                                        c.fillStyle = Skin.dim;
                                        c.beginPath();
                                        c.moveTo(1, 0);
                                        c.lineTo(width, height / 2);
                                        c.lineTo(1, height);
                                        c.closePath();
                                        c.fill();
                                    }
                                }
                            }
                        }
                    }
                }

                // ---------------------------------------- POWER
                Panel {
                    width: panels.colW
                    height: panels.colH
                    title: "POWER"
                    chipText: SysState.charging ? "CHARGING"
                        : SysState.onBattery ? "BATTERY" : "PLUGGED"
                    chipColor: SysState.charging ? Skin.accent : Skin.dim

                    Column {
                        width: parent.width

                        // Battery: display only, no focus.
                        Item {
                            width: parent.width
                            height: 56

                            Row {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12

                                BatteryIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 30
                                    height: 16
                                    fraction: SysState.hp
                                    color: Skin.body
                                    fillColor: Skin.hpColor(SysState.hp)
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    Text {
                                        text: Math.round(SysState.hp * 100) + "%"
                                        color: Skin.text
                                        font.family: Skin.fontLabel
                                        font.bold: true
                                        font.pixelSize: 20
                                    }

                                    Text {
                                        text: win.batterySub
                                        color: Skin.dim
                                        font.family: Skin.fontLabel
                                        font.pixelSize: 10
                                        font.letterSpacing: 10 * 0.08
                                    }
                                }
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Skin.inner }

                        SubLabel { text: "PROFILE" }

                        // Three cells; return (or a tap on one) cycles /
                        // picks. The chosen profile is the gold cell -- gold
                        // marks a persistent pick, pink marks where keyboard
                        // focus sits (the row border).
                        FocusRow {
                            width: parent.width
                            height: 36
                            active: win.foc(2, 0)
                            onTapped: win.tapRow(2, 0)

                            Row {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Repeater {
                                    model: win.perfModes

                                    Rectangle {
                                        required property var modelData

                                        readonly property bool current:
                                            PowerProfiles.profile === modelData.profile

                                        width: (panels.colW - 24 - 12) / 3
                                        height: 24
                                        color: current ? Skin.window : "transparent"
                                        border.width: current ? 2 : 1
                                        border.color: current ? Skin.accent : Skin.inner

                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.modelData.label
                                            color: parent.current ? Skin.text : Skin.dim
                                            font.family: Skin.fontLabel
                                            font.bold: parent.current
                                            font.pixelSize: 9
                                            font.letterSpacing: 9 * 0.10
                                        }

                                        TapHandler {
                                            onTapped: {
                                                win.pIdx = 2;
                                                win.rIdx = 0;
                                                PowerProfiles.profile
                                                    = parent.modelData.profile;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Brightness: bars only, deliberately no number
                        // (backlight percent is meaningless; the OSD says
                        // the same).
                        FocusRow {
                            width: parent.width
                            height: 34
                            active: win.foc(2, 1)
                            onTapped: win.tapRow(2, 1)

                            Row {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24
                                spacing: 10

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "sun"
                                    size: 15
                                    color: Skin.body
                                }

                                StepMeter {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 15 - 10
                                    height: 12
                                    steps: 8
                                    value: SysState.bright8
                                    fillColor: Skin.accent
                                    onStepClicked: n => SysState.setBright8(n)
                                }
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Skin.inner }

                        FocusRow {
                            width: parent.width
                            height: 28
                            active: win.foc(2, 2)
                            onTapped: win.tapRow(2, 2)

                            Row {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "moon"
                                    size: 13
                                    color: Skin.body
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "NIGHT LIGHT"
                                    color: Skin.body
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 10
                                    font.letterSpacing: 10 * 0.12
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: win.warm ? "WARM" : "OFF"
                                color: win.warm ? Skin.accent : Skin.dim
                                font.family: Skin.fontLabel
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }
                        }

                        FocusRow {
                            width: parent.width
                            height: 28
                            active: win.foc(2, 3)
                            onTapped: win.tapRow(2, 3)

                            Row {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "bellOff"
                                    size: 13
                                    color: Skin.body
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "DO NOT DISTURB"
                                    color: Skin.body
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 10
                                    font.letterSpacing: 10 * 0.12
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: Notifs.dnd ? "ON" : "OFF"
                                color: Notifs.dnd ? Skin.accent : Skin.dim
                                font.family: Skin.fontLabel
                                font.bold: Notifs.dnd
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }
                        }

                        FocusRow {
                            width: parent.width
                            height: 28
                            active: win.foc(2, 4)
                            onTapped: win.tapRow(2, 4)

                            Text {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: "TIMEZONE"
                                color: Skin.body
                                font.family: Skin.fontLabel
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: win.timezone.toUpperCase() || "—"
                                color: Skin.text
                                font.family: Skin.fontLabel
                                font.bold: true
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.08
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------------ vitals

            Rectangle {
                id: vitals
                x: 16
                y: panels.y + panels.height + 12
                width: deck.width - 32
                height: 62
                color: "transparent"
                border.width: 2
                border.color: Skin.inner

                Row {
                    x: 2
                    y: 2
                    height: parent.height - 4

                    Vital {
                        label: "CPU"
                        value: Math.round(SysState.cpuPct * 100) + "%"
                        frac: SysState.cpuPct
                    }

                    Rectangle { width: 1; height: parent.height; color: Skin.inner }

                    Vital {
                        label: "MEM"
                        value: ((SysState.memTotalKb - SysState.memAvailKb) / 1048576).toFixed(1)
                               + " / " + Math.round(SysState.memTotalKb / 1048576) + "G"
                        frac: 1 - SysState.memFreeFraction
                    }

                    Rectangle { width: 1; height: parent.height; color: Skin.inner }

                    Vital {
                        label: "TEMP"
                        value: SysState.tempC + "°C"
                        frac: SysState.tempC / 90
                        hue: SysState.tempC >= 90 ? Skin.critical
                             : SysState.tempC >= 75 ? Skin.warn : Skin.accent
                    }

                    Rectangle { width: 1; height: parent.height; color: Skin.inner }

                    Vital {
                        label: "DISK"
                        value: (SysState.diskSizeG - SysState.diskAvailG)
                               + " / " + SysState.diskSizeG + "G"
                        frac: SysState.diskSizeG > 0
                            ? (SysState.diskSizeG - SysState.diskAvailG) / SysState.diskSizeG
                            : 0
                    }
                }
            }

            // ------------------------------------------------------ footer

            Text {
                id: footer
                x: 16
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                text: "TAB PANEL · ↑↓ ROW · ⏎ APPLY · ESC CLOSE"
                color: Skin.dim
                font.family: Skin.fontLabel
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.12
            }
        }
    }

    // ---------------------------------------------------------------- pieces

    // A bordered panel with a titlebar strip and a state chip on its right.
    component Panel: Rectangle {
        id: panel

        property string title: ""
        property string chipText: ""
        property color chipColor: Skin.dim
        signal chipTapped()
        default property alias content: body.data

        color: "transparent"
        border.width: 2
        border.color: Skin.inner

        Rectangle {
            id: panelStrip
            x: 2
            y: 2
            width: parent.width - 4
            height: 26
            color: Skin.cell

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Skin.inner
            }

            Text {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: panel.title
                color: Skin.text
                font.family: Skin.fontLabel
                font.bold: true
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.12
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: panel.chipText
                color: panel.chipColor
                font.family: Skin.fontLabel
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.12

                TapHandler {
                    onTapped: panel.chipTapped()
                }
            }
        }

        Item {
            id: body
            x: 2
            y: panelStrip.y + panelStrip.height
            width: parent.width - 4
            height: parent.height - panelStrip.height - 4
            clip: true
        }
    }

    // A focusable row: pink 2px border and window fill while (panel, row)
    // focus sits on it; tap moves focus here and applies.
    component FocusRow: Rectangle {
        property bool active: false
        property color baseColor: "transparent"
        signal tapped()

        color: active ? Skin.window : baseColor
        border.width: active ? 2 : 0
        border.color: Skin.snd

        TapHandler {
            onTapped: parent.tapped()
        }
    }

    component SubLabel: Text {
        x: 12
        topPadding: 7
        bottomPadding: 3
        color: Skin.dim
        font.family: Skin.fontLabel
        font.pixelSize: 9
        font.letterSpacing: 9 * 0.14
    }

    // One vitals cell: label, figure, 8-block meter.
    component Vital: Item {
        property string label: ""
        property string value: ""
        property real frac: 0
        property color hue: Skin.accent

        width: (vitals.width - 4 - 3) / 4
        height: parent.height

        Column {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 24
            spacing: 6

            Item {
                width: parent.width
                height: 12

                Text {
                    text: label
                    color: Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 9
                    font.letterSpacing: 9 * 0.14
                }

                Text {
                    anchors.right: parent.right
                    text: value
                    color: Skin.text
                    font.family: Skin.fontLabel
                    font.bold: true
                    font.pixelSize: 11
                }
            }

            StepMeter {
                width: parent.width
                height: 8
                steps: 8
                value: Math.max(0, Math.min(8, Math.round(frac * 8)))
                fillColor: hue
            }
        }
    }
}
