// The CONNECT panel, turns 25f-25j: a real Wi-Fi + Bluetooth manager read
// as an encounter screen. The machine is the actor -- it uses CONNECT on
// targets; outcomes are effectiveness, never percentages. Known networks and
// paired devices are REGISTERED, like dex entries -- records of encounters,
// never a collection the machine owns. FORGET deletes the dex entry.
//
// Backends are the native Quickshell modules end to end: Quickshell.Networking
// for Wi-Fi (scan, connect, PSK, forget -- no nmcli scraping) and
// Quickshell.Bluetooth for devices. The one thing BlueZ does not expose
// through the module is the pairing confirmation code, so a bluetoothctl
// side-process registers as the agent while the BLUETOOTH tab is open and
// feeds the 25j dialog.
//
// Scanning is gated on visibility, per the shell's no-background-probing
// doctrine: the Wi-Fi scanner and the Bluetooth discovery run only while
// their tab is on screen.
//
// If the panel is closed when an outcome lands, it is delivered as a toast
// through Notifs.push (turn 25k) instead of the log box.

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland

PanelWindow {
    id: win

    signal dismissed()
    // Asks the shell to open this panel (TRY AGAIN on an outcome toast).
    signal requestOpen()

    property string tab: "wifi"

    // Selection is tracked by name, not index: the scan reorders the model
    // under the outline.
    property string wifiSel: ""
    property string btSel: ""

    // "", "password" (25g) or "pair" (25j).
    property string dialog: ""
    property string psk: ""
    property string pairCode: ""
    property var pairDevice: null

    // The network an attempt is in flight on.
    property var pending: null

    // Append-only battle text, capped to the visible lines. Entries are
    // { t, strong } -- outcome lines render in `text`, narration in `body`.
    property var log: []

    // SSIDs already announced as wild appearances.
    property var seenNets: ({})

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
    WlrLayershell.namespace: "rpg-connect"

    onVisibleChanged: {
        if (visible) {
            dialog = "";
            psk = "";
            log = [];
            seenNets = ({});
            keys.forceActiveFocus();
        }
    }

    // ---------------- wifi state

    readonly property var wifiDev: {
        const ds = Networking.devices.values;
        for (let i = 0; i < ds.length; i++)
            if (ds[i].type === DeviceType.Wifi) return ds[i];
        return null;
    }

    // Scan only while the tab is on screen. Binding restores the previous
    // value (off) when `when` drops.
    Binding {
        target: win.wifiDev
        property: "scannerEnabled"
        value: true
        when: win.wifiDev !== null && win.visible && win.tab === "wifi"
    }

    // The double's range is not documented; normalise either 0-1 or 0-100
    // into the 8-block meter.
    function sig8(s) {
        const f = s <= 1 ? s : s / 100;
        return Math.max(0, Math.min(8, Math.round(f * 8)));
    }

    readonly property var wifiNets: {
        if (!wifiDev) return [];
        const ns = wifiDev.networks.values
            .filter(n => n.name !== "")
            .sort((a, b) => b.signalStrength - a.signalStrength);
        // Six rows keeps the whole panel inside the 720 logical panel with
        // the log box and legend below it.
        return ns.slice(0, 6);
    }

    onWifiNetsChanged: {
        if (!visible || tab !== "wifi") return;
        wifiNets.forEach(n => {
            if (!seenNets[n.name]) {
                seenNets[n.name] = true;
                pushLog("A wild " + n.name + " appeared!", false);
            }
        });
    }

    // ---------------- bluetooth state

    readonly property var btAdapter: Bluetooth.defaultAdapter

    Binding {
        target: win.btAdapter
        property: "discovering"
        value: true
        when: win.btAdapter !== null && win.btAdapter.enabled
              && win.visible && win.tab === "bluetooth"
    }

    // BlueZ names an anonymous device after its address; those rows (and
    // one-character scan ghosts) are noise, not targets.
    function btNamed(d) {
        const n = d.deviceName || d.name || "";
        if (n.length < 3) return false;
        return !/^([0-9a-f]{2}[-:]){5}[0-9a-f]{2}$/i.test(n);
    }

    readonly property var btDevices: {
        if (!btAdapter) return [];
        const ds = Bluetooth.devices.values
            .filter(btNamed)
            .sort((a, b) => {
                const ka = (a.connected ? 0 : a.paired ? 1 : 2);
                const kb = (b.connected ? 0 : b.paired ? 1 : 2);
                return ka !== kb ? ka - kb
                    : (a.deviceName || a.name).localeCompare(b.deviceName || b.name);
            });
        return ds.slice(0, 6);
    }

    onBtDevicesChanged: {
        if (!visible || tab !== "bluetooth") return;
        btDevices.forEach(d => {
            const name = d.deviceName || d.name;
            if (!seenNets["bt:" + name]) {
                seenNets["bt:" + name] = true;
                pushLog("A wild " + name.toUpperCase() + " appeared!", false);
            }
        });
    }

    function btTypeChip(d) {
        const icon = d.icon || "";
        if (icon.indexOf("audio") === 0 || icon.indexOf("headset") >= 0
            || icon.indexOf("headphone") >= 0) return "AUDIO";
        if (icon.indexOf("input") === 0) return "INPUT";
        if (icon.indexOf("phone") >= 0) return "PHONE";
        return "";
    }

    // The BlueZ pairing agent: registered only while the BLUETOOTH tab is
    // open, so pair requests raised from this panel land in the 25j dialog.
    // Everything else bluetoothctl prints is ignored.
    Process {
        id: btAgent
        command: ["bluetoothctl"]
        running: win.visible && win.tab === "bluetooth"
        stdinEnabled: true
        onStarted: write("agent DisplayYesNo\ndefault-agent\n")
        stdout: SplitParser {
            onRead: data => {
                const line = data.replace(/\x1b\[[0-9;]*m/g, "");
                const m = line.match(/Confirm passkey (\d+)/);
                if (m) {
                    win.pairCode = m[1].length === 6
                        ? m[1].slice(0, 3) + " " + m[1].slice(3)
                        : m[1];
                    win.dialog = "pair";
                }
            }
        }
    }

    // ---------------- selection / actions

    readonly property var rows: tab === "wifi" ? wifiNets : btDevices
    readonly property string sel: tab === "wifi" ? wifiSel : btSel

    function rowName(r) {
        return tab === "wifi" ? r.name : (r.deviceName || r.name);
    }

    readonly property int selIndex: {
        for (let i = 0; i < rows.length; i++)
            if (rowName(rows[i]) === sel) return i;
        return rows.length > 0 ? 0 : -1;
    }

    readonly property var selRow: selIndex >= 0 ? rows[selIndex] : null

    function moveSel(dy) {
        if (rows.length === 0) return;
        const next = Math.max(0, Math.min(rows.length - 1, selIndex + dy));
        if (tab === "wifi") wifiSel = rowName(rows[next]);
        else btSel = rowName(rows[next]);
    }

    function pushLog(line, strong) {
        log = log.concat([{ t: line, strong: !!strong }]).slice(-3);
    }

    function attempt(net) {
        pending = net;
        pushLog(Skin.species + " used CONNECT on " + net.name + "...", false);
        outcomeGuard.restart();
        if (dialog === "password") {
            dialog = "";
            net.connectWithPsk(psk);
            psk = "";
        } else {
            net.connect();
        }
    }

    function act() {
        if (!selRow) return;
        if (tab === "wifi") {
            const net = selRow;
            if (net.connected) {
                net.disconnect();
                pushLog(Skin.species + " withdrew from " + net.name + ".", false);
                return;
            }
            if (net.known || net.security === WifiSecurityType.Open) {
                attempt(net);
            } else {
                psk = "";
                dialog = "password";
            }
            return;
        }
        const d = selRow;
        if (d.pairing) return;
        if (!d.paired) {
            pairDevice = d;
            d.pair();
            pushLog(Skin.species + " used CONNECT on "
                    + (d.deviceName || d.name).toUpperCase() + "...", false);
        } else if (d.connected) {
            d.disconnect();
            pushLog(Skin.species + " withdrew from "
                    + (d.deviceName || d.name).toUpperCase() + ".", false);
        } else {
            btPending = d;
            pushLog(Skin.species + " used CONNECT on "
                    + (d.deviceName || d.name).toUpperCase() + "...", false);
            outcomeGuard.restart();
            d.connect();
        }
    }

    // ---------------- outcomes (25h / 25k)

    property var btPending: null

    function outcome(target, ok, reason) {
        outcomeGuard.stop();
        if (ok) {
            if (visible) {
                pushLog("It was super effective!", true);
            } else {
                Notifs.push({
                    tag: "NET", target: target,
                    chip: "SUPER EFFECTIVE", chipColor: Skin.ok,
                    line: Skin.species + " used CONNECT on " + target
                          + ". It was super effective!"
                });
            }
            return;
        }
        if (reason === "avoided") {
            if (visible) {
                pushLog(target + " avoided the attack!", true);
                dialog = "password";
            } else {
                const net = pending;
                Notifs.push({
                    tag: "NET", target: target, critical: true,
                    chip: "AVOIDED", chipColor: Skin.critical,
                    line: Skin.species + " used CONNECT on " + target + ". "
                          + target + " avoided the attack!",
                    actions: [
                        { label: "TRY AGAIN", act: () => {
                            win.tab = "wifi";
                            win.wifiSel = target;
                            win.dialog = "password";
                            win.requestOpen();
                        } },
                        { label: "FORGET", act: () => {
                            if (net) net.forget();
                        } }
                    ]
                });
            }
            return;
        }
        if (visible) {
            pushLog("But it failed!", true);
        } else {
            Notifs.push({
                tag: "NET", target: target, critical: true,
                chip: "FAILED", chipColor: Skin.critical,
                line: Skin.species + " used CONNECT on " + target
                      + ", but it failed!",
                subline: "TARGET OUT OF RANGE OR HELD BY ANOTHER MACHINE"
            });
        }
    }

    Connections {
        target: win.pending
        ignoreUnknownSignals: true

        function onConnectedChanged(): void {
            if (win.pending && win.pending.connected) {
                const t = win.pending.name;
                const p = win.pending;
                win.pending = null;
                win.outcome(t, true, "");
                // pending cleared before outcome so a late signal can't
                // double-report; p kept alive by the closure until here.
            }
        }

        function onConnectionFailed(reason): void {
            if (!win.pending) return;
            const t = win.pending.name;
            const avoided = reason === ConnectionFailReason.NoSecrets
                         || reason === ConnectionFailReason.WifiAuthTimeout;
            if (!avoided) win.pending = null;
            win.outcome(t, false, avoided ? "avoided" : "failed");
        }
    }

    Connections {
        target: win.btPending
        ignoreUnknownSignals: true

        function onConnectedChanged(): void {
            if (win.btPending && win.btPending.connected) {
                const t = (win.btPending.deviceName || win.btPending.name).toUpperCase();
                win.btPending = null;
                win.outcome(t, true, "");
            }
        }
    }

    Connections {
        target: win.pairDevice
        ignoreUnknownSignals: true

        function onPairedChanged(): void {
            if (win.pairDevice && win.pairDevice.paired) {
                const t = (win.pairDevice.deviceName || win.pairDevice.name).toUpperCase();
                win.pairDevice = null;
                win.dialog = "";
                win.outcome(t, true, "");
            }
        }
    }

    // Nothing native signals a Bluetooth connect failure or a stalled Wi-Fi
    // attempt reliably; after 30s an attempt with no answer is a miss.
    Timer {
        id: outcomeGuard
        interval: 30000
        onTriggered: {
            const p = win.pending || win.btPending;
            if (!p) return;
            const t = win.pending ? win.pending.name
                    : (win.btPending.deviceName || win.btPending.name).toUpperCase();
            win.pending = null;
            win.btPending = null;
            win.outcome(t, false, "failed");
        }
    }

    // ---------------- input

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        TapHandler {
            onTapped: eventPoint => {
                const active = win.dialog !== "" ? dialogFrame : mainFrame;
                const p = active.mapFromItem(keys,
                    eventPoint.position.x, eventPoint.position.y);
                if (p.x < 0 || p.y < 0 || p.x > active.width || p.y > active.height)
                    win.dismissed();
            }
        }

        Keys.onPressed: event => {
            if (win.dialog === "password") {
                switch (event.key) {
                case Qt.Key_Escape:
                    win.dialog = "";
                    win.psk = "";
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (win.selRow && win.psk !== "") win.attempt(win.selRow);
                    break;
                case Qt.Key_Backspace:
                    win.psk = win.psk.slice(0, -1);
                    break;
                default:
                    if (event.text && event.text.length === 1 && event.text >= " ")
                        win.psk += event.text;
                    else
                        return;
                }
                event.accepted = true;
                return;
            }

            if (win.dialog === "pair") {
                switch (event.key) {
                case Qt.Key_Escape:
                    btAgent.write("no\n");
                    if (win.pairDevice) win.pairDevice.cancelPair();
                    win.pairDevice = null;
                    win.dialog = "";
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    btAgent.write("yes\n");
                    win.dialog = "";
                    break;
                default:
                    return;
                }
                event.accepted = true;
                return;
            }

            switch (event.key) {
            case Qt.Key_Escape:
                win.dismissed();
                break;
            case Qt.Key_Up:      win.moveSel(-1); break;
            case Qt.Key_Down:    win.moveSel(1); break;
            case Qt.Key_Left:
            case Qt.Key_Right:
            case Qt.Key_Tab:
                win.tab = win.tab === "wifi" ? "bluetooth" : "wifi";
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                win.act();
                break;
            case Qt.Key_Delete:
                if (win.tab === "wifi" && win.selRow && win.selRow.known)
                    win.selRow.forget();
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        // ---------------- the panel (25f / 25i)

        Frame {
            id: mainFrame
            visible: win.dialog === ""
            anchors.centerIn: parent
            width: 760
            padTop: 24
            padSide: 12
            padBottom: 12
            title: "CONNECT"

            Column {
                width: mainFrame.width - 2 * (5 + 12)
                spacing: 12

                // Tab row.
                Row {
                    spacing: 8

                    Repeater {
                        model: ["WIFI", "BLUETOOTH"]

                        Rectangle {
                            id: tabCell

                            required property string modelData

                            readonly property bool active:
                                win.tab === (modelData === "WIFI" ? "wifi" : "bluetooth")

                            implicitWidth: tabText.implicitWidth + 36
                            implicitHeight: tabText.implicitHeight + 16
                            color: active ? Skin.outer : Skin.strip

                            Text {
                                id: tabText
                                anchors.centerIn: parent
                                text: tabCell.modelData
                                color: tabCell.active ? Skin.window : Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 12
                                font.letterSpacing: 12 * 0.18
                            }

                            TapHandler {
                                onTapped: win.tab =
                                    tabCell.modelData === "WIFI" ? "wifi" : "bluetooth"
                            }
                        }
                    }
                }

                // Target list.
                Rectangle {
                    width: parent.width
                    height: listCol.implicitHeight + 16
                    color: Skin.strip
                    border.width: 4
                    border.color: Skin.inner

                    Column {
                        id: listCol
                        x: 8
                        y: 8
                        width: parent.width - 16
                        spacing: 6

                        Repeater {
                            model: win.rows

                            Rectangle {
                                id: row

                                required property var modelData
                                required property int index

                                readonly property bool active: win.selIndex === index
                                readonly property string label:
                                    win.tab === "wifi"
                                        ? modelData.name
                                        : (modelData.deviceName || modelData.name).toUpperCase()

                                width: listCol.width
                                height: 46
                                color: Skin.cell

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right
                                    anchors.rightMargin: 14
                                    spacing: 12

                                    // Wi-Fi: LINKED, REGISTERED, SECURED, meter.
                                    Rectangle {
                                        visible: win.tab === "wifi" && row.modelData.connected
                                        anchors.verticalCenter: parent.verticalCenter
                                        implicitWidth: linkedText.implicitWidth + 14
                                        implicitHeight: linkedText.implicitHeight + 6
                                        color: Skin.inner

                                        Text {
                                            id: linkedText
                                            anchors.centerIn: parent
                                            text: "LINKED"
                                            color: Skin.text
                                            font.family: "Silkscreen"
                                            font.pixelSize: 10
                                            font.letterSpacing: 10 * 0.16
                                        }
                                    }

                                    Rectangle {
                                        visible: win.tab === "wifi" && row.modelData.known
                                        anchors.verticalCenter: parent.verticalCenter
                                        implicitWidth: knownText.implicitWidth + 14
                                        implicitHeight: knownText.implicitHeight + 6
                                        color: Skin.inner

                                        Text {
                                            id: knownText
                                            anchors.centerIn: parent
                                            text: "REGISTERED"
                                            color: Skin.text
                                            font.family: "Silkscreen"
                                            font.pixelSize: 10
                                            font.letterSpacing: 10 * 0.16
                                        }
                                    }

                                    Rectangle {
                                        visible: win.tab === "wifi"
                                            && row.modelData.security !== WifiSecurityType.Open
                                        anchors.verticalCenter: parent.verticalCenter
                                        implicitWidth: securedText.implicitWidth + 14
                                        implicitHeight: securedText.implicitHeight + 6
                                        color: "transparent"
                                        border.width: 2
                                        border.color: Skin.dim

                                        Text {
                                            id: securedText
                                            anchors.centerIn: parent
                                            text: "SECURED"
                                            color: Skin.dim
                                            font.family: "Silkscreen"
                                            font.pixelSize: 10
                                            font.letterSpacing: 10 * 0.16
                                        }
                                    }

                                    Meter {
                                        visible: win.tab === "wifi"
                                        anchors.verticalCenter: parent.verticalCenter
                                        blocks: 8
                                        filled: win.tab === "wifi"
                                            ? win.sig8(row.modelData.signalStrength) : 0
                                        blockWidth: 6
                                        blockHeight: 14
                                        spacing: 2
                                        fillColor: Skin.accent
                                        ticks: false
                                        shine: false
                                    }

                                    // Bluetooth: CHARGE, type chip, state chip.
                                    Text {
                                        visible: win.tab === "bluetooth"
                                            && row.modelData.batteryAvailable === true
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: win.tab === "bluetooth"
                                            ? "CHARGE " + Math.round((row.modelData.battery || 0) * 100)
                                            : ""
                                        color: Skin.dim
                                        font.family: "Silkscreen"
                                        font.pixelSize: 10
                                        font.letterSpacing: 10 * 0.14
                                    }

                                    Rectangle {
                                        visible: win.tab === "bluetooth"
                                            && win.btTypeChip(row.modelData) !== ""
                                        anchors.verticalCenter: parent.verticalCenter
                                        implicitWidth: typeText.implicitWidth + 14
                                        implicitHeight: typeText.implicitHeight + 6
                                        color: "transparent"
                                        border.width: 2
                                        border.color: Skin.dim

                                        Text {
                                            id: typeText
                                            anchors.centerIn: parent
                                            text: win.tab === "bluetooth"
                                                ? win.btTypeChip(row.modelData) : ""
                                            color: Skin.dim
                                            font.family: "Silkscreen"
                                            font.pixelSize: 10
                                            font.letterSpacing: 10 * 0.16
                                        }
                                    }

                                    Rectangle {
                                        visible: win.tab === "bluetooth"
                                            && (row.modelData.connected || row.modelData.paired)
                                        anchors.verticalCenter: parent.verticalCenter
                                        implicitWidth: stateText.implicitWidth + 14
                                        implicitHeight: stateText.implicitHeight + 6
                                        color: Skin.inner

                                        Text {
                                            id: stateText
                                            anchors.centerIn: parent
                                            text: win.tab === "bluetooth"
                                                ? (row.modelData.connected ? "LINKED" : "REGISTERED")
                                                : ""
                                            color: Skin.text
                                            font.family: "Silkscreen"
                                            font.pixelSize: 10
                                            font.letterSpacing: 10 * 0.16
                                        }
                                    }
                                }

                                Text {
                                    x: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 28
                                           - (win.tab === "wifi" ? 340 : 260)
                                    text: row.label
                                    color: row.active ? Skin.text : Skin.body
                                    elide: Text.ElideRight
                                    font.family: "Silkscreen"
                                    font.pixelSize: 12
                                    font.letterSpacing: 12 * 0.06
                                }

                                Rectangle {
                                    visible: row.active
                                    anchors.fill: parent
                                    color: "transparent"
                                    border.width: 3
                                    border.color: Skin.outline
                                }

                                TapHandler {
                                    onTapped: {
                                        if (win.tab === "wifi") win.wifiSel = row.label;
                                        else win.btSel = row.label;
                                        win.act();
                                    }
                                }
                            }
                        }

                        // Empty scan.
                        Column {
                            visible: win.rows.length === 0
                            width: listCol.width
                            topPadding: 34
                            bottomPadding: 38
                            spacing: 10

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Skin.emptyWord
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 14
                                font.letterSpacing: 14 * 0.18
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Nothing answered the search."
                                color: Skin.body
                                font.family: "DotGothic16"
                                font.pixelSize: 16
                            }
                        }
                    }
                }

                // Log box, below the list (the ordering matters, 25f).
                Rectangle {
                    width: parent.width
                    height: logCol.implicitHeight + 32
                    color: Skin.strip
                    border.width: 4
                    border.color: Skin.inner

                    Column {
                        id: logCol
                        x: 16
                        y: 14
                        width: parent.width - 32
                        spacing: 5

                        Repeater {
                            model: win.log.length > 0 ? win.log
                                : [{ t: "What will " + Skin.species + " do?", strong: false }]

                            Text {
                                required property var modelData

                                width: logCol.width
                                text: modelData.t
                                color: modelData.strong ? Skin.text : Skin.body
                                wrapMode: Text.Wrap
                                font.family: "DotGothic16"
                                font.pixelSize: 16
                            }
                        }
                    }

                    Blink {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        width: logMark.implicitWidth
                        height: logMark.implicitHeight

                        Text {
                            id: logMark
                            text: "▼"
                            color: Skin.accent
                            font.family: "Silkscreen"
                            font.pixelSize: 12
                        }
                    }
                }

                // Action row: FORGET for a selected known network + legend.
                Item {
                    width: parent.width
                    height: Math.max(forgetBtn.height, legend.implicitHeight)

                    Rectangle {
                        id: forgetBtn
                        visible: win.tab === "wifi" && win.selRow !== null
                                 && win.selRow.known === true
                        implicitWidth: forgetText.implicitWidth + 36
                        implicitHeight: forgetText.implicitHeight + 18
                        color: Skin.cell
                        border.width: 3
                        border.color: Skin.critical

                        Text {
                            id: forgetText
                            anchors.centerIn: parent
                            text: "FORGET"
                            color: Skin.critical
                            font.family: "Silkscreen"
                            font.pixelSize: 12
                            font.letterSpacing: 12 * 0.16
                        }

                        TapHandler {
                            onTapped: if (win.selRow) win.selRow.forget()
                        }
                    }

                    Text {
                        id: legend
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↑↓ SELECT · ↵ "
                              + (win.selRow && win.selRow.connected ? "RELEASE" : "CONNECT")
                              + " · ESC CLOSE"
                        color: Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.16
                    }
                }
            }
        }

        // ---------------- password dialog (25g)

        Frame {
            id: dialogFrame
            visible: win.dialog !== ""
            anchors.centerIn: parent
            width: 560
            padTop: 24
            padSide: 12
            padBottom: 12
            title: "CONNECT"

            // Password variant.
            Rectangle {
                visible: win.dialog === "password"
                width: dialogFrame.width - 2 * (5 + 12)
                height: visible ? pwCol.implicitHeight + 36 : 0
                color: Skin.strip
                border.width: 4
                border.color: Skin.inner

                Column {
                    id: pwCol
                    x: 18
                    y: 16
                    width: parent.width - 36
                    spacing: 14

                    Text {
                        width: parent.width
                        text: (win.selRow ? win.selRow.name : "THE TARGET")
                              + " WANTS A PASSWORD"
                        color: Skin.text
                        wrapMode: Text.Wrap
                        lineHeight: 1.5
                        font.family: "Silkscreen"
                        font.pixelSize: 12
                        font.letterSpacing: 12 * 0.10
                    }

                    Rectangle {
                        width: parent.width
                        height: maskRow.implicitHeight + 24
                        color: Skin.cell
                        border.width: 3
                        border.color: Skin.inner

                        Row {
                            id: maskRow
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "•".repeat(win.psk.length)
                                color: Skin.text
                                font.family: "Silkscreen"
                                font.pixelSize: 14
                                font.letterSpacing: 14 * 0.24
                            }

                            Blink {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 9
                                height: 18

                                Rectangle {
                                    width: 9
                                    height: 18
                                    color: Skin.accent
                                }
                            }
                        }
                    }

                    Text {
                        text: "↵ CONNECT · ESC CANCEL"
                        color: Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.16
                    }
                }
            }

            // Pair variant (25j).
            Rectangle {
                visible: win.dialog === "pair"
                width: dialogFrame.width - 2 * (5 + 12)
                height: visible ? pairCol.implicitHeight + 40 : 0
                color: Skin.strip
                border.width: 4
                border.color: Skin.inner

                Column {
                    id: pairCol
                    x: 20
                    y: 18
                    width: parent.width - 40
                    spacing: 14

                    Row {
                        spacing: 12

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.pairDevice
                                ? (win.pairDevice.deviceName || win.pairDevice.name).toUpperCase()
                                : "THE TARGET"
                            color: Skin.text
                            font.family: "Silkscreen"
                            font.pixelSize: 12
                            font.letterSpacing: 12 * 0.10
                        }

                        Rectangle {
                            visible: win.pairDevice !== null
                                     && win.btTypeChip(win.pairDevice) !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: pairTypeText.implicitWidth + 14
                            implicitHeight: pairTypeText.implicitHeight + 6
                            color: "transparent"
                            border.width: 2
                            border.color: Skin.dim

                            Text {
                                id: pairTypeText
                                anchors.centerIn: parent
                                text: win.pairDevice ? win.btTypeChip(win.pairDevice) : ""
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.16
                            }
                        }
                    }

                    Text {
                        text: win.pairCode
                        color: Skin.text
                        font.family: "Silkscreen"
                        font.pixelSize: 34
                        font.letterSpacing: 34 * 0.16
                    }

                    Text {
                        text: "CODES MUST MATCH"
                        color: Skin.accent
                        font.family: "Silkscreen"
                        font.pixelSize: 12
                        font.letterSpacing: 12 * 0.16
                    }

                    Row {
                        spacing: 8

                        Rectangle {
                            implicitWidth: pairYes.implicitWidth + 36
                            implicitHeight: pairYes.implicitHeight + 18
                            color: Skin.accent

                            Text {
                                id: pairYes
                                anchors.centerIn: parent
                                text: "PAIR"
                                color: Skin.bg
                                font.family: "Silkscreen"
                                font.pixelSize: 12
                                font.letterSpacing: 12 * 0.16
                            }

                            TapHandler {
                                onTapped: {
                                    btAgent.write("yes\n");
                                    win.dialog = "";
                                }
                            }
                        }

                        Rectangle {
                            implicitWidth: pairNo.implicitWidth + 36
                            implicitHeight: pairNo.implicitHeight + 18
                            color: Skin.cell
                            border.width: 3
                            border.color: Skin.inner

                            Text {
                                id: pairNo
                                anchors.centerIn: parent
                                text: "CANCEL"
                                color: Skin.dim
                                font.family: "Silkscreen"
                                font.pixelSize: 12
                                font.letterSpacing: 12 * 0.16
                            }

                            TapHandler {
                                onTapped: {
                                    btAgent.write("no\n");
                                    if (win.pairDevice) win.pairDevice.cancelPair();
                                    win.pairDevice = null;
                                    win.dialog = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
