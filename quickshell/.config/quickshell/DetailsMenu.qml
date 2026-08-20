// The details menu, from turn 17a of the creature-shell handoff: the control
// panel as a real game menu, ONE layer deep -- every section shows its whole
// contents with the controls in place, and there are no drill-in pages.
//
// Left rail: SUMMARY / STATS / ABILITIES / ITEMS / MOVES / TRAINABLE /
// SESSION, plus the nature + caught plate. Right pane: that section's
// contents. Keys: up/down row, left/right section, return toggles, ESC
// closes. `mSec` is the section NAME, never an index -- an index-keyed
// version of this menu shipped an off-by-one (decision log).
//
// Everything shown is real: HP is the battery, the IVs are the hardware,
// MUSIC is MPRIS, WIFI is NetworkManager, ITEMS is bluez, MOVES is the
// process table, POWER MODE is power-profiles-daemon. The expensive figures
// (per-process CPU, wifi detail) poll only while this surface is visible.
//
// One knowing deviation: SESSION's RESTART and SHUT DOWN ask first, and the
// asking is the power menu's red log line -- the rows here hand over to the
// same confirm flow instead of duplicating it.

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

    // Section by NAME. Never an index.
    property string mSec: "SUMMARY"
    property int mRow: 0

    readonly property var sections: ["SUMMARY", "STATS", "ABILITIES", "ITEMS",
                                     "MOVES", "TRAINABLE", "SESSION"]

    readonly property int rowCount: {
        switch (mSec) {
        case "ABILITIES": return 2;
        case "ITEMS":     return 1;
        case "TRAINABLE": return 3;
        case "SESSION":   return 4;
        default:          return 0;
        }
    }

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

    onVisibleChanged: {
        SysState.menuWants = visible;
        if (visible) {
            mSec = "SUMMARY";
            mRow = 0;
            keys.forceActiveFocus();
            refresh();
        }
    }

    function refresh() {
        if (!topProcs.running) topProcs.running = true;
        if (!wifiDetail.running) wifiDetail.running = true;
    }

    Timer {
        running: win.visible
        interval: 5000
        repeat: true
        onTriggered: win.refresh()
    }

    // ---------------------------------------------------------------- gated data

    // Top processes by CPU. One ps per refresh tick, menu-visible only.
    property var procRows: []
    property int procMore: 0

    Process {
        id: topProcs
        command: ["ps", "-eo", "comm=,pcpu=,rss="]
        stdout: StdioCollector {
            onStreamFinished: {
                const byName = {};
                let count = 0;
                text.split("\n").forEach(line => {
                    const parts = line.trim().split(/\s+/);
                    if (parts.length < 3) return;
                    const rss = parseInt(parts[parts.length - 1], 10) || 0;
                    const cpu = parseFloat(parts[parts.length - 2]) || 0;
                    const name = parts.slice(0, parts.length - 2).join(" ");
                    if (!byName[name]) { byName[name] = { name: name, cpu: 0, rss: 0 }; count++; }
                    byName[name].cpu += cpu;
                    byName[name].rss += rss;
                });
                const rows = Object.values(byName)
                    .sort((a, b) => b.cpu - a.cpu || b.rss - a.rss)
                    .slice(0, 4);
                win.procRows = rows;
                win.procMore = Math.max(0, count - 4);
            }
        }
    }

    // Wifi detail beyond the bar's link/signal: rate and IP.
    property string wifiRate: ""
    property string wifiIp: "—"

    Process {
        id: wifiDetail
        command: ["sh", "-c",
            "nmcli -t -f ACTIVE,RATE,CHAN dev wifi | grep '^yes' | head -1; " +
            "nmcli -t -g IP4.ADDRESS device show 2>/dev/null | grep -m1 ."]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length > 0 && lines[0].startsWith("yes")) {
                    const parts = lines[0].split(":");
                    win.wifiRate = (parts[1] || "") + " — CHANNEL " + (parts[2] || "?");
                } else {
                    win.wifiRate = SysState.wifiUp ? "" : "RADIO OFF";
                }
                win.wifiIp = lines.length > 1 ? lines[1].split("/")[0] : "—";
            }
        }
    }

    // Months since the machine was caught (the root filesystem's birth).
    property string caught: "CAUGHT — UNKNOWN"

    Process {
        id: caughtQuery
        command: ["stat", "-c", "%W", "/"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const born = parseInt(text.trim(), 10);
                if (!born || born <= 0) return;
                const months = Math.floor((Date.now() / 1000 - born) / 2629800);
                win.caught = "CAUGHT " + months + " MONTHS AGO";
            }
        }
    }

    // TMs: installed, teachable, not running.
    readonly property var tmRows: {
        const apps = DesktopEntries.applications.values;
        const out = [];
        let more = 0;
        for (let i = 0; i < apps.length; i++) {
            const entry = apps[i];
            if (entry.noDisplay) continue;
            const match = Apps.processName(entry);
            if (match !== "" && Apps.windowsFor(match) > 0) continue;
            if (out.length < 5)
                out.push({ name: (entry.name || "").toUpperCase(),
                           tag: Apps.categoryOf(entry) });
            else
                more++;
        }
        return { rows: out, more: more };
    }

    // MPRIS.
    readonly property var player: {
        const players = Mpris.players.values;
        for (let i = 0; i < players.length; i++)
            if (players[i].playbackState === MprisPlaybackState.Playing) return players[i];
        return players.length > 0 ? players[0] : null;
    }

    function mmss(s) {
        if (!s || s < 0) return "0:00";
        return Math.floor(s / 60) + ":" + (Math.floor(s % 60) < 10 ? "0" : "") + Math.floor(s % 60);
    }

    // Bluetooth.
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btDevices: {
        const out = [];
        if (!btAdapter || !btAdapter.enabled) return out;
        const devs = Bluetooth.devices.values;
        for (let i = 0; i < devs.length; i++)
            if (devs[i].connected) out.push(devs[i]);
        return out;
    }

    // Power mode.
    readonly property var perfModes: [
        { label: "QUIET", profile: PowerProfile.PowerSaver,
          note: "Fans quiet. Clocks capped. HP drains slowest." },
        { label: "BALANCED", profile: PowerProfile.Balanced,
          note: "Default. Clock scales with load." },
        { label: "MEGA", profile: PowerProfile.Performance,
          note: "All cores unlocked. Fans loud, HP drains faster." }
    ]

    function cyclePerf() {
        const cur = PowerProfiles.profile;
        for (let i = 0; i < perfModes.length; i++) {
            if (perfModes[i].profile === cur) {
                PowerProfiles.profile = perfModes[(i + 1) % perfModes.length].profile;
                return;
            }
        }
        PowerProfiles.profile = PowerProfile.Balanced;
    }

    // ---------------------------------------------------------------- toggle

    function toggle() {
        switch (mSec) {
        case "ABILITIES":
            if (mRow === 0 && player) player.togglePlaying();
            else if (mRow === 1)
                Quickshell.execDetached(["nmcli", "radio", "wifi",
                                         SysState.wifiUp ? "off" : "on"]);
            break;
        case "ITEMS":
            if (btAdapter) btAdapter.enabled = !btAdapter.enabled;
            break;
        case "TRAINABLE":
            if (mRow === 0) SysState.setVolPct(
                SysState.volPct >= 100 ? 0 : SysState.volPct + 5);
            else if (mRow === 1) SysState.setBright8((SysState.bright8 % 8) + 1);
            else cyclePerf();
            break;
        case "SESSION":
            switch (mRow) {
            case 0: Quickshell.execDetached(["loginctl", "lock-session"]); win.dismissed(); break;
            case 1: Quickshell.execDetached(["systemctl", "suspend"]); win.dismissed(); break;
            // Restart and shut down ask first -- in the power menu's red
            // log line, which owns that flow.
            default: win.dismissed(); Quickshell.execDetached(["qs", "ipc", "call", "power", "toggle"]);
            }
            break;
        }
    }

    // ---------------------------------------------------------------- input

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        TapHandler {
            onTapped: win.dismissed()
        }

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_Right: {
                const step = event.key === Qt.Key_Right ? 1 : -1;
                const i = win.sections.indexOf(win.mSec);
                win.mSec = win.sections[(i + step + win.sections.length) % win.sections.length];
                win.mRow = 0;
                break;
            }
            case Qt.Key_Up:
                win.mRow = Math.max(0, win.mRow - 1);
                break;
            case Qt.Key_Down:
                win.mRow = Math.min(Math.max(0, win.rowCount - 1), win.mRow + 1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                win.toggle();
                break;
            case Qt.Key_Escape:
                win.dismissed();
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        Frame {
            width: 940
            anchors.centerIn: parent
            title: Skin.species

            padTop: 26
            padSide: 20
            padBottom: 18

            TapHandler {
                onTapped: {}
            }

            Column {
                width: parent.width
                spacing: 14

                // ---- header: crumb + key state
                Item {
                    width: parent.width
                    height: crumbRow.implicitHeight + 12

                    Row {
                        id: crumbRow
                        spacing: 12

                        Blink {
                            anchors.verticalCenter: parent.verticalCenter
                            width: crumbCursor.implicitWidth
                            height: crumbCursor.implicitHeight

                            Text {
                                id: crumbCursor
                                text: "▶"
                                color: Skin.accent
                                font.family: "Silkscreen"
                                font.pixelSize: 14
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Skin.species + " · " + win.mSec
                            color: Skin.text
                            font.family: "Silkscreen"
                            font.pixelSize: 16
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: crumbRow.verticalCenter
                        text: "KEYS ARMED — ESC RELEASES"
                        color: Skin.accent
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.16
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 4
                        color: Skin.inner
                    }
                }

                // ---- rail + pane
                Row {
                    width: parent.width
                    spacing: 16

                    // left rail
                    Column {
                        id: rail
                        width: 196
                        spacing: 8

                        Repeater {
                            model: win.sections

                            Rectangle {
                                id: tab

                                required property string modelData

                                readonly property bool active: win.mSec === modelData

                                width: rail.width
                                height: 38
                                color: active ? Skin.accent : Skin.cell
                                border.width: 3
                                border.color: active ? Skin.accent : Skin.inner

                                Rectangle {
                                    z: -1
                                    y: 4
                                    width: parent.width
                                    height: parent.height
                                    color: Skin.shadow
                                }

                                Row {
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 9

                                    Text {
                                        text: "▸"
                                        color: tab.active ? Skin.shadow : Skin.dim
                                        font.family: "Silkscreen"
                                        font.pixelSize: 12
                                    }

                                    Text {
                                        text: tab.modelData
                                        color: tab.active ? Skin.shadow : Skin.body
                                        font.family: "Silkscreen"
                                        font.pixelSize: 12
                                        font.letterSpacing: 12 * 0.10
                                    }
                                }

                                TapHandler {
                                    onTapped: {
                                        win.mSec = tab.modelData;
                                        win.mRow = 0;
                                    }
                                }
                            }
                        }

                        // nature + caught plate
                        Rectangle {
                            width: rail.width
                            height: naturePlate.implicitHeight + 22
                            color: Skin.strip
                            border.width: 3
                            border.color: Skin.inner

                            Column {
                                id: naturePlate
                                x: 12
                                y: 11
                                spacing: 5

                                Text {
                                    text: Skin.nature
                                    color: Skin.dim
                                    font.family: "Silkscreen"
                                    font.pixelSize: 10
                                    font.letterSpacing: 10 * 0.14
                                }

                                Text {
                                    text: win.caught
                                    color: Skin.dim
                                    font.family: "Silkscreen"
                                    font.pixelSize: 10
                                    font.letterSpacing: 10 * 0.12
                                }
                            }
                        }
                    }

                    // right pane
                    Rectangle {
                        id: pane
                        width: parent.width - rail.width - 16
                        height: Math.max(rail.implicitHeight + 120, paneLoader.implicitHeight + 40)
                        color: Skin.strip
                        border.width: 4
                        border.color: Skin.inner

                        // inset 0 0 0 2px shadow keyline
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            color: "transparent"
                            border.width: 2
                            border.color: Skin.shadow
                        }

                        // floating tab naming the section
                        Rectangle {
                            x: 14
                            y: -9
                            width: paneTab.implicitWidth + 18
                            height: paneTab.implicitHeight + 6
                            color: Skin.inner

                            Text {
                                id: paneTab
                                anchors.centerIn: parent
                                text: win.mSec
                                color: Skin.text
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.2
                            }
                        }

                        Loader {
                            id: paneLoader
                            x: 18
                            y: 20
                            width: parent.width - 36
                            sourceComponent: {
                                switch (win.mSec) {
                                case "SUMMARY":   return summarySec;
                                case "STATS":     return statsSec;
                                case "ABILITIES": return abilitiesSec;
                                case "ITEMS":     return itemsSec;
                                case "MOVES":     return movesSec;
                                case "TRAINABLE": return trainSec;
                                default:          return sessionSec;
                                }
                            }
                        }
                    }
                }

                // ---- key legend
                Row {
                    width: parent.width
                    spacing: 10

                    Rectangle {
                        width: parent.width
                        height: 4
                        color: Skin.inner
                        visible: false
                    }

                    Repeater {
                        model: [
                            { key: "↑ ↓", what: "ROW" },
                            { key: "← →", what: "SECTION" },
                            { key: "↵", what: "TOGGLE" },
                            { key: "ESC", what: "CLOSE" }
                        ]

                        Row {
                            required property var modelData
                            spacing: 8

                            Rectangle {
                                width: legendKey.implicitWidth + 16
                                height: legendKey.implicitHeight + 8
                                color: Skin.cell
                                border.width: 3
                                border.color: Skin.inner

                                Text {
                                    id: legendKey
                                    anchors.centerIn: parent
                                    text: parent.parent.modelData.key
                                    color: Skin.body
                                    font.family: "Silkscreen"
                                    font.pixelSize: 10
                                    font.letterSpacing: 10 * 0.14
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.modelData.what
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.14
                            }
                        }
                    }
                }
            }
        }
    }

    // ================================================================ sections

    // ---------------- SUMMARY
    Component {
        id: summarySec

        Row {
            spacing: 18

            // portrait
            Rectangle {
                width: 216
                height: 196
                color: Skin.cell
                border.width: 3
                border.color: Skin.inner

                Image {
                    id: portrait
                    anchors.fill: parent
                    anchors.margins: 8
                    source: Quickshell.env("HOME") + "/.config/quickshell/assets/ally-front.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: false
                    visible: status === Image.Ready
                    asynchronous: true
                }

                DashedSlot {
                    anchors.fill: parent
                    anchors.margins: 8
                    label: "PORTRAIT"
                    visible: !portrait.visible
                }
            }

            Column {
                width: parent.width - 216 - 18
                spacing: 11

                Item {
                    width: parent.width
                    height: sumName.implicitHeight

                    Text {
                        id: sumName
                        text: Skin.species
                        color: Skin.text
                        font.family: "Silkscreen"
                        font.pixelSize: 20
                    }

                    Text {
                        x: sumName.implicitWidth + 10
                        anchors.baseline: sumName.baseline
                        text: "LV " + Skin.level
                        color: Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 12
                        font.letterSpacing: 12 * 0.14
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 7

                        Rectangle {
                            width: sumT1.implicitWidth + 16
                            height: sumT1.implicitHeight + 6
                            color: Skin.type1Hue

                            Text {
                                id: sumT1
                                anchors.centerIn: parent
                                text: Skin.type1
                                color: Skin.shadow
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.18
                            }
                        }

                        Rectangle {
                            visible: Skin.type2 !== "" && Skin.type2 !== "-"
                            width: sumT2.implicitWidth + 16
                            height: sumT2.implicitHeight + 6
                            color: Skin.type2Hue

                            Text {
                                id: sumT2
                                anchors.centerIn: parent
                                text: Skin.type2
                                color: Skin.shadow
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.18
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 10

                    Text {
                        id: sumHpLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: "HP"
                        color: Skin.outer
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.16
                    }

                    HpBar {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - sumHpLabel.implicitWidth - sumHpNum.implicitWidth - 20
                        height: 11
                        fraction: SysState.hp
                        fillColor: Skin.hpColor(SysState.hp)
                        alarm: SysState.hp <= 0.2
                    }

                    Text {
                        id: sumHpNum
                        anchors.verticalCenter: parent.verticalCenter
                        text: SysState.hpNum
                        color: Skin.body
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                    }
                }

                Row {
                    width: parent.width
                    spacing: 10

                    Text {
                        id: sumExpLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: "EXP"
                        color: Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.16
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - sumExpLabel.implicitWidth - sumExpNum.implicitWidth - 20
                        height: 6
                        color: Skin.inner

                        Rectangle {
                            readonly property real frac:
                                (SysState.clock.date.getHours() * 3600
                                 + SysState.clock.date.getMinutes() * 60) / 86400
                            width: Math.round(parent.width * frac)
                            height: parent.height
                            color: Skin.net
                        }
                    }

                    Text {
                        id: sumExpNum
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const frac = (SysState.clock.date.getHours() * 3600
                                + SysState.clock.date.getMinutes() * 60) / 86400;
                            return "EXP TO NEXT LV — " + (100 - Math.round(frac * 100)) + "%";
                        }
                        color: Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                    }
                }

                Grid {
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 6

                    Text {
                        width: 84
                        text: "ABILITY"
                        color: Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.14
                    }
                    Text {
                        text: Skin.ability
                        color: Skin.text
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                    }

                    Text {
                        width: 84
                        text: "HELD"
                        color: Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.14
                    }
                    Text {
                        text: SysState.heldItem + " — "
                              + (SysState.onBattery ? "ON BATTERY" : "ON CHARGE")
                        color: Skin.text
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                    }

                    Text {
                        width: 84
                        text: "STATUS"
                        color: Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.14
                    }
                    Row {
                        spacing: 5

                        Repeater {
                            model: SysState.chips
                            Chip {
                                required property var modelData
                                label: modelData.label
                                hue: modelData.hue
                            }
                        }

                        Chip {
                            visible: SysState.sub
                            label: "SUB"
                            hue: Skin.accent
                            fieldEffect: true
                        }

                        Text {
                            visible: SysState.chips.length === 0 && !SysState.sub
                            text: "NONE"
                            color: Skin.dim
                            font.family: "Silkscreen"
                            font.pixelSize: 10
                        }
                    }
                }

                // HARDWARE plate: the IVs.
                Rectangle {
                    width: parent.width
                    height: ivCol.implicitHeight + 20
                    color: Skin.strip
                    border.width: 3
                    border.color: Skin.inner

                    Column {
                        id: ivCol
                        x: 12
                        y: 10
                        spacing: 6

                        Text {
                            text: "HARDWARE — FIXED AT BIRTH"
                            color: Skin.dim
                            font.family: "Silkscreen"
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.18
                        }

                        Row {
                            spacing: 18

                            Repeater {
                                model: SysState.ivRows

                                Row {
                                    required property var modelData
                                    spacing: 7

                                    Text {
                                        anchors.baseline: ivVal.baseline
                                        text: modelData.label
                                        color: Skin.dim
                                        font.family: "Silkscreen"
                                        font.pixelSize: 10
                                        font.letterSpacing: 10 * 0.12
                                    }

                                    Text {
                                        id: ivVal
                                        text: modelData.val
                                        color: Skin.text
                                        font.family: "Silkscreen"
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: Skin.crNote
                    color: Skin.body
                    font.family: "DotGothic16"
                    font.pixelSize: 16
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ---------------- STATS
    Component {
        id: statsSec

        Column {
            spacing: 10

            Repeater {
                model: SysState.statRows

                Rectangle {
                    required property var modelData

                    width: parent.width
                    height: 44
                    color: Skin.cell

                    Column {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 96
                        spacing: 2

                        Text {
                            text: parent.parent.modelData.label
                            color: Skin.text
                            font.family: "Silkscreen"
                            font.pixelSize: 12
                        }

                        Text {
                            text: parent.parent.modelData.sub
                            color: Skin.dim
                            font.family: "Silkscreen"
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.10
                        }
                    }

                    HpBar {
                        x: 118
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 118 - 160
                        height: 11
                        fraction: parent.modelData.frac
                        fillColor: parent.modelData.hue
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.val
                        color: Skin.body
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.06
                    }
                }
            }

            Text {
                text: Skin.nature + " — NATURE SHAPES NOTHING YET"
                color: Skin.accent
                font.family: "Silkscreen"
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.12
            }

            Rectangle {
                width: parent.width
                height: capsCol.implicitHeight + 24
                color: Skin.strip
                border.width: 3
                border.color: Skin.inner

                Column {
                    id: capsCol
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 7

                    Text {
                        text: "HARDWARE CAPS — WHY THE STATS STOP WHERE THEY DO"
                        color: Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.18
                    }

                    Repeater {
                        model: SysState.ivRows

                        Row {
                            required property var modelData
                            spacing: 10

                            Text {
                                width: 62
                                text: modelData.label
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }

                            Text {
                                width: 88
                                text: modelData.val
                                color: Skin.text
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                            }

                            Text {
                                text: modelData.note
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }
                        }
                    }
                }
            }

            Row {
                spacing: 9

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CONDITIONS"
                    color: Skin.dim
                    font.family: "Silkscreen"
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.18
                }

                Repeater {
                    model: SysState.chips
                    Chip {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        label: modelData.label
                        hue: modelData.hue
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "BRN — THERMAL THROTTLE · SLP — SUSPEND · SUB — DO NOT DISTURB"
                    color: Skin.dim
                    font.family: "Silkscreen"
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.10
                }
            }
        }
    }

    // ---------------- ABILITIES
    Component {
        id: abilitiesSec

        Column {
            spacing: 12

            // MUSIC -- full width, own controls. The ability toggle lives on
            // the header row only.
            Rectangle {
                width: parent.width
                height: musicCol.implicitHeight + 26
                color: Skin.cell
                border.width: 3
                border.color: win.mSec === "ABILITIES" && win.mRow === 0
                    ? Skin.outline : Skin.inner

                Column {
                    id: musicCol
                    x: 14
                    y: 13
                    width: parent.width - 28
                    spacing: 11

                    Item {
                        width: parent.width
                        height: musicName.implicitHeight + 6

                        Row {
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "▸"
                                color: win.mRow === 0 ? Skin.accent : Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 12
                            }

                            Text {
                                id: musicName
                                anchors.verticalCenter: parent.verticalCenter
                                text: "MUSIC"
                                color: Skin.text
                                font.family: "Silkscreen"
                                font.pixelSize: 12
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            width: musicChip.implicitWidth + 14
                            height: musicChip.implicitHeight + 6
                            color: win.player && win.player.playbackState === MprisPlaybackState.Playing
                                ? Skin.accent : Skin.inner

                            Text {
                                id: musicChip
                                anchors.centerIn: parent
                                text: win.player && win.player.playbackState === MprisPlaybackState.Playing
                                    ? "PLAYING" : "IDLE"
                                color: win.player && win.player.playbackState === MprisPlaybackState.Playing
                                    ? Skin.shadow : Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.14
                            }

                            TapHandler {
                                onTapped: if (win.player) win.player.togglePlaying()
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: Math.max(trackCol.implicitHeight, transport.implicitHeight)

                        Column {
                            id: trackCol
                            width: parent.width - transport.implicitWidth - 14
                            spacing: 6

                            Text {
                                width: parent.width
                                text: win.player ? (win.player.trackTitle || "NOTHING QUEUED").toUpperCase() : "NO PLAYER"
                                color: Skin.text
                                font.family: "Silkscreen"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: win.player ? (win.player.trackArtist || "").toUpperCase() : ""
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                                elide: Text.ElideRight
                            }

                            Row {
                                width: parent.width
                                spacing: 9

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - npTime.implicitWidth - 9
                                    height: 7
                                    color: Skin.inner

                                    Rectangle {
                                        width: {
                                            const p = win.player;
                                            if (!p || !p.length || p.length <= 0) return 0;
                                            return Math.round(parent.width
                                                * Math.max(0, Math.min(1, p.position / p.length)));
                                        }
                                        height: parent.height
                                        color: Skin.snd
                                    }
                                }

                                Text {
                                    id: npTime
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: win.player
                                        ? win.mmss(win.player.position) + " / " + win.mmss(win.player.length)
                                        : ""
                                    color: Skin.dim
                                    font.family: "Silkscreen"
                                    font.pixelSize: 10
                                }
                            }
                        }

                        Row {
                            id: transport
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Repeater {
                                model: [
                                    { glyph: "◀◀", accent: false },
                                    { glyph: "▶⏸", accent: true },
                                    { glyph: "▶▶", accent: false }
                                ]

                                Rectangle {
                                    required property var modelData
                                    required property int index

                                    width: 42
                                    height: 34
                                    color: Skin.strip
                                    border.width: 3
                                    border.color: modelData.accent ? Skin.accent : Skin.inner

                                    Rectangle {
                                        z: -1
                                        y: 4
                                        width: parent.width
                                        height: parent.height
                                        color: Skin.shadow
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData.glyph
                                        color: parent.modelData.accent ? Skin.accent : Skin.body
                                        font.family: "Silkscreen"
                                        font.pixelSize: 10
                                    }

                                    TapHandler {
                                        onTapped: {
                                            if (!win.player) return;
                                            if (parent.index === 0) win.player.previous();
                                            else if (parent.index === 1) win.player.togglePlaying();
                                            else win.player.next();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: outLabel.implicitHeight

                        Row {
                            spacing: 10

                            Text {
                                id: outLabel
                                text: "OUT"
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.16
                            }

                            Text {
                                text: SysState.sink && SysState.sink.description
                                    ? SysState.sink.description.toUpperCase() : "—"
                                color: Skin.body
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                            }
                        }

                        Text {
                            anchors.right: parent.right
                            text: SysState.volPct === 0 ? "THROAT CHOP"
                                : SysState.volPct >= 100 ? "BOOMBURST"
                                : SysState.volPct + "%"
                            color: Skin.text
                            font.family: "Silkscreen"
                            font.pixelSize: 10
                        }
                    }

                    // MUSIC's own volume meter: 20 bars of 5%, clicking a
                    // block sets it.
                    StepMeter {
                        width: parent.width
                        height: 16
                        steps: 20
                        value: SysState.vol20
                        onStepClicked: n => SysState.setVolPct(n * 5)
                    }
                }
            }

            // WIFI
            Rectangle {
                width: parent.width
                height: wifiCol.implicitHeight + 26
                color: Skin.cell
                border.width: 3
                border.color: win.mSec === "ABILITIES" && win.mRow === 1
                    ? Skin.outline : Skin.inner

                Column {
                    id: wifiCol
                    x: 14
                    y: 13
                    width: parent.width - 28
                    spacing: 10

                    Item {
                        width: parent.width
                        height: wifiTitle.implicitHeight + 6

                        Row {
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "▸"
                                color: win.mRow === 1 ? Skin.accent : Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 12
                            }

                            Text {
                                id: wifiTitle
                                anchors.verticalCenter: parent.verticalCenter
                                text: "WIFI"
                                color: Skin.text
                                font.family: "Silkscreen"
                                font.pixelSize: 12
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            width: wifiChip.implicitWidth + 14
                            height: wifiChip.implicitHeight + 6
                            color: SysState.wifiUp ? Skin.accent : Skin.inner

                            Text {
                                id: wifiChip
                                anchors.centerIn: parent
                                text: SysState.wifiUp ? "CONNECTED" : "OFF"
                                color: SysState.wifiUp ? Skin.shadow : Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.14
                            }

                            TapHandler {
                                onTapped: Quickshell.execDetached(
                                    ["nmcli", "radio", "wifi", SysState.wifiUp ? "off" : "on"])
                            }
                        }
                    }

                    Row {
                        spacing: 4

                        Repeater {
                            model: 4

                            Rectangle {
                                required property int index
                                anchors.bottom: parent.bottom
                                width: 12
                                height: [10, 16, 22, 26][index]
                                color: index < SysState.wifiBars ? Skin.accent : Skin.inner
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 10
                            spacing: 3

                            Text {
                                text: SysState.wifiUp ? SysState.ssid.toUpperCase() : "NO LINK"
                                color: Skin.text
                                font.family: "Silkscreen"
                                font.pixelSize: 12
                            }

                            Text {
                                text: win.wifiRate
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.10
                            }
                        }
                    }

                    Row {
                        spacing: 10

                        Text {
                            width: 52
                            text: "IP"
                            color: Skin.dim
                            font.family: "Silkscreen"
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.14
                        }

                        Text {
                            text: win.wifiIp
                            color: Skin.body
                            font.family: "Silkscreen"
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }

    // ---------------- ITEMS
    Component {
        id: itemsSec

        Column {
            spacing: 12

            // radio toggle at the top; ABILITIES holds only MUSIC and WIFI.
            Rectangle {
                width: parent.width
                height: 44
                color: Skin.cell
                border.width: 3
                border.color: win.mSec === "ITEMS" && win.mRow === 0
                    ? Skin.outline : Skin.inner

                Row {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "▸"
                        color: win.mRow === 0 ? Skin.accent : Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "BLUETOOTH RADIO"
                        color: Skin.text
                        font.family: "Silkscreen"
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: btChip.implicitWidth + 14
                    height: btChip.implicitHeight + 6
                    color: win.btAdapter && win.btAdapter.enabled ? Skin.accent : Skin.inner

                    Text {
                        id: btChip
                        anchors.centerIn: parent
                        text: win.btAdapter && win.btAdapter.enabled ? "ON" : "OFF"
                        color: win.btAdapter && win.btAdapter.enabled ? Skin.shadow : Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.14
                    }
                }

                TapHandler {
                    onTapped: if (win.btAdapter) win.btAdapter.enabled = !win.btAdapter.enabled
                }
            }

            // held items: what the machine connected to. Radio off empties
            // the list -- the machine holds nothing it is not connected to.
            Repeater {
                model: win.btDevices

                Rectangle {
                    required property var modelData

                    width: parent.width
                    height: itemCol.implicitHeight + 24
                    color: Skin.cell
                    border.width: 3
                    border.color: Skin.inner

                    Column {
                        id: itemCol
                        x: 12
                        y: 12
                        width: parent.width - 24
                        spacing: 9

                        Item {
                            width: parent.width
                            height: itemName.implicitHeight

                            Text {
                                id: itemName
                                text: (parent.parent.parent.modelData.name || "DEVICE").toUpperCase()
                                color: Skin.text
                                font.family: "Silkscreen"
                                font.pixelSize: 12
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.baseline: itemName.baseline
                                text: "CONNECTED"
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 10
                            visible: parent.parent.modelData.batteryAvailable

                            Text {
                                id: chargeLabel
                                anchors.verticalCenter: parent.verticalCenter
                                text: "CHARGE"
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.16
                            }

                            HpBar {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - chargeLabel.implicitWidth - chargePct.implicitWidth - 20
                                height: 10
                                fraction: parent.parent.parent.modelData.battery
                                fillColor: Skin.hpColor(parent.parent.parent.modelData.battery)
                            }

                            Text {
                                id: chargePct
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.round(parent.parent.parent.modelData.battery * 100) + "%"
                                color: Skin.hpColor(parent.parent.parent.modelData.battery)
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }

            Text {
                text: win.btAdapter && win.btAdapter.enabled
                    ? (win.btDevices.length === 0 ? "NO DEVICE HELD" : "NO OTHER DEVICE PAIRED")
                    : "RADIO OFF — NOTHING HELD"
                color: Skin.dim
                font.family: "Silkscreen"
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.12
            }
        }
    }

    // ---------------- MOVES
    Component {
        id: movesSec

        Column {
            spacing: 9

            Repeater {
                model: win.procRows

                Rectangle {
                    required property var modelData

                    width: parent.width
                    height: moveCol.implicitHeight + 22
                    color: Skin.cell
                    border.width: 3
                    border.color: Skin.inner

                    Column {
                        id: moveCol
                        x: 12
                        y: 11
                        width: parent.width - 24
                        spacing: 8

                        Item {
                            width: parent.width
                            height: procName.implicitHeight

                            Text {
                                id: procName
                                text: parent.parent.parent.modelData.name.toUpperCase()
                                color: Skin.text
                                font.family: "Silkscreen"
                                font.pixelSize: 12
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.baseline: procName.baseline
                                text: "PP " + Math.max(0,
                                    Math.round(SysState.memTotalKb / 1024 / 1024)
                                    - Math.ceil(parent.parent.parent.modelData.rss / 1024 / 1024))
                                    + "/" + Math.round(SysState.memTotalKb / 1024 / 1024)
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.10
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 8

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44
                                text: "CPU"
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.14
                            }

                            HpBar {
                                anchors.verticalCenter: parent.verticalCenter
                                width: (parent.width - 44 - 58 - 44 - 58 - 40) / 2
                                height: 8
                                fraction: Math.min(1, parent.parent.parent.modelData.cpu / 100)
                                fillColor: Skin.cmd
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 58
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(parent.parent.parent.modelData.cpu) + "%"
                                color: Skin.body
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44
                                text: "MEM"
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.14
                            }

                            HpBar {
                                anchors.verticalCenter: parent.verticalCenter
                                width: (parent.width - 44 - 58 - 44 - 58 - 40) / 2
                                height: 8
                                fraction: SysState.memTotalKb > 0
                                    ? parent.parent.parent.modelData.rss / SysState.memTotalKb : 0
                                fillColor: Skin.dim
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 58
                                horizontalAlignment: Text.AlignRight
                                text: (parent.parent.parent.modelData.rss / 1024 / 1024).toFixed(1) + "G"
                                color: Skin.body
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }

            Text {
                text: "+ " + win.procMore + " BACKGROUND PROCESSES"
                color: Skin.dim
                font.family: "Silkscreen"
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.12
            }

            Rectangle {
                width: parent.width
                height: tmCol.implicitHeight + 24
                color: Skin.strip
                border.width: 3
                border.color: Skin.inner

                Column {
                    id: tmCol
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 8

                    Text {
                        text: "INSTALLED — TEACHABLE, NOT RUNNING"
                        color: Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.18
                    }

                    Flow {
                        width: parent.width
                        spacing: 7

                        Repeater {
                            model: win.tmRows.rows

                            Rectangle {
                                required property var modelData

                                width: tmRow.implicitWidth + 16
                                height: tmRow.implicitHeight + 10
                                color: Skin.cell
                                border.width: 3
                                border.color: Skin.inner

                                Row {
                                    id: tmRow
                                    anchors.centerIn: parent
                                    spacing: 7

                                    Text {
                                        text: parent.parent.modelData.tag
                                        color: Skin.categoryColor(parent.parent.modelData.tag)
                                        font.family: "Silkscreen"
                                        font.pixelSize: 10
                                        font.letterSpacing: 10 * 0.14
                                    }

                                    Text {
                                        text: parent.parent.modelData.name
                                        color: Skin.body
                                        font.family: "Silkscreen"
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        text: win.tmRows.more + " MORE INSTALLED — NOT RUNNING"
                        color: Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.12
                    }
                }
            }
        }
    }

    // ---------------- TRAINABLE
    Component {
        id: trainSec

        Column {
            spacing: 16

            Column {
                width: parent.width
                spacing: 6

                Item {
                    width: parent.width
                    height: volLabel.implicitHeight

                    Row {
                        spacing: 10

                        Text {
                            id: volLabel
                            text: "VOLUME"
                            color: win.mRow === 0 ? Skin.text : Skin.body
                            font.family: "Silkscreen"
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.14
                        }

                        Text {
                            text: SysState.vol20 + " / 20"
                            color: Skin.dim
                            font.family: "Silkscreen"
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.10
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        text: SysState.volPct === 0 ? "THROAT CHOP"
                            : SysState.volPct >= 100 ? "BOOMBURST"
                            : SysState.volPct + "%"
                        color: Skin.text
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                    }
                }

                StepMeter {
                    width: parent.width
                    height: 22
                    steps: 20
                    value: SysState.vol20
                    outlined: win.mRow === 0
                    onStepClicked: n => SysState.setVolPct(n * 5)
                }
            }

            Column {
                width: parent.width
                spacing: 6

                Item {
                    width: parent.width
                    height: brLabel.implicitHeight

                    Row {
                        spacing: 10

                        Text {
                            id: brLabel
                            text: "BRIGHTNESS"
                            color: win.mRow === 1 ? Skin.text : Skin.body
                            font.family: "Silkscreen"
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.14
                        }

                        Text {
                            text: SysState.bright8 + " / 8"
                            color: Skin.dim
                            font.family: "Silkscreen"
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.10
                        }
                    }

                    // Brightness shows no percent -- the bars are the
                    // readout; only the extremes get a name.
                    Text {
                        anchors.right: parent.right
                        text: SysState.bright8 === 0 ? "BLACK HOLE ECLIPSE"
                            : SysState.bright8 >= 8 ? "LIGHT THAT BURNS THE SKY"
                            : ""
                        color: Skin.text
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                    }
                }

                StepMeter {
                    width: parent.width
                    height: 22
                    value: SysState.bright8
                    fillColor: Skin.outer
                    outlined: win.mRow === 1
                    onStepClicked: n => SysState.setBright8(n)
                }
            }

            Column {
                width: parent.width
                spacing: 9

                Text {
                    text: "POWER MODE"
                    color: win.mRow === 2 ? Skin.text : Skin.dim
                    font.family: "Silkscreen"
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.18
                }

                Row {
                    width: parent.width
                    spacing: 9

                    Repeater {
                        model: win.perfModes

                        Rectangle {
                            required property var modelData

                            readonly property bool active: PowerProfiles.profile === modelData.profile

                            width: (parent.width - 18) / 3
                            height: 40
                            color: active ? Skin.accent : Skin.cell
                            border.width: 3
                            border.color: active ? Skin.accent : Skin.inner

                            Rectangle {
                                z: -1
                                y: 4
                                width: parent.width
                                height: parent.height
                                color: Skin.shadow
                            }

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                color: parent.active ? Skin.shadow : Skin.body
                                font.family: "Silkscreen"
                                font.pixelSize: 12
                            }

                            TapHandler {
                                onTapped: PowerProfiles.profile = parent.modelData.profile
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: {
                        for (let i = 0; i < win.perfModes.length; i++)
                            if (win.perfModes[i].profile === PowerProfiles.profile)
                                return win.perfModes[i].note;
                        return "";
                    }
                    color: Skin.dim
                    font.family: "Silkscreen"
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.12
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ---------------- SESSION
    Component {
        id: sessionSec

        Column {
            spacing: 12

            Grid {
                columns: 2
                columnSpacing: 10
                rowSpacing: 10
                width: parent.width

                Repeater {
                    model: [
                        { name: "LOCK", key: "SUPER + L", danger: false },
                        { name: "SLEEP", key: "CLOSE LID", danger: false },
                        { name: "RESTART", key: "SUPER + ESC", danger: false },
                        { name: "SHUT DOWN", key: "SUPER + ESC", danger: true }
                    ]

                    Rectangle {
                        required property var modelData
                        required property int index

                        readonly property bool active:
                            win.mSec === "SESSION" && win.mRow === index

                        width: (parent.width - 10) / 2
                        height: 62
                        color: Skin.cell
                        border.width: 3
                        border.color: modelData.danger ? Skin.critical
                            : active ? Skin.outline : Skin.inner

                        Rectangle {
                            z: -1
                            y: 4
                            width: parent.width
                            height: parent.height
                            color: Skin.shadow
                        }

                        Column {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5

                            Text {
                                text: parent.parent.modelData.name
                                color: parent.parent.modelData.danger ? Skin.critical : Skin.text
                                font.family: "Silkscreen"
                                font.pixelSize: 12
                            }

                            Text {
                                text: parent.parent.modelData.key
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }
                        }

                        TapHandler {
                            onTapped: {
                                win.mRow = parent.index;
                                win.toggle();
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: "Restart and shut down ask first — the capture device holds the confirmation."
                color: Skin.body
                font.family: "DotGothic16"
                font.pixelSize: 16
                wrapMode: Text.WordWrap
            }
        }
    }
}
