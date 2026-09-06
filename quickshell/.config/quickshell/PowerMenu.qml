// The power menu: five session actions in a row of icon tiles (Console
// dress), each with its real keybind, and one line under the row saying what
// the highlighted action does. Confirmation is a red-framed log line with
// YES / NO -- not a second menu. Plain wording by default; the creature
// voice comes back through the power_* lexicon keys and the per-creature
// ball word on the titlebar.
//
// The key hints are this machine's actual binds, not the design's: LOCK is
// SUPER+L, LOG OUT is SUPER+SHIFT+L (hyprland.lua). RESTART joined the row
// with the Console redesign -- it used to be reachable only through the
// details menu's SESSION rows, which still land here via openConfirm().

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win

    signal dismissed()

    property int selected: 0

    // null, or the action awaiting a YES/NO.
    property var confirming: null
    property bool confirmYes: false

    readonly property var actions: [
        {
            name: "LOCK", icon: "lock", key: "SUPER + L",
            danger: false, confirm: false,
            note: "Stays awake.",
            run: ["loginctl", "lock-session"]
        },
        {
            name: "LOG OUT", icon: "logout", key: "SUPER + SHIFT + L",
            danger: false, confirm: true,
            note: "Ends the session. Open apps close.",
            run: ["hyprctl", "dispatch", "exit"]
        },
        {
            name: "SUSPEND", icon: "moon", key: "CLOSE LID",
            danger: false, confirm: false,
            note: "Sleeps. Resumes where you left off.",
            run: ["systemctl", "suspend"]
        },
        {
            name: "RESTART", icon: "reboot", key: "",
            danger: false, confirm: true,
            note: "Reboots. The machine comes right back.",
            run: ["systemctl", "reboot"]
        },
        {
            name: "SHUT DOWN", icon: "power", key: "HOLD POWER",
            danger: true, confirm: true,
            note: "Full stop.",
            run: ["systemctl", "poweroff"]
        }
    ]

    // Open straight onto the confirm line for a named action (the details
    // menu's SESSION rows). Unknown names leave the plain row up.
    function openConfirm(name) {
        for (let i = 0; i < actions.length; i++) {
            if (actions[i].name === name && actions[i].confirm) {
                confirming = actions[i];
                confirmYes = false;
                selected = i;
                return;
            }
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
    WlrLayershell.namespace: "shell-power"

    onVisibleChanged: {
        if (visible) {
            selected = 0;
            confirming = null;
            keys.forceActiveFocus();
        }
    }

    function activate(action) {
        if (action.confirm && win.confirming === null) {
            win.confirming = action;
            win.confirmYes = false;
            return;
        }
        Quickshell.execDetached(action.run);
        win.dismissed();
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        // Dismiss only on a click OUTSIDE the frame.
        TapHandler {
            onTapped: eventPoint => {
                const p = powerFrame.mapFromItem(keys,
                    eventPoint.position.x, eventPoint.position.y);
                if (p.x < 0 || p.y < 0 || p.x > powerFrame.width || p.y > powerFrame.height)
                    win.dismissed();
            }
        }

        Keys.onPressed: event => {
            if (win.confirming !== null) {
                switch (event.key) {
                case Qt.Key_Left:
                case Qt.Key_Right:
                    win.confirmYes = !win.confirmYes;
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (win.confirmYes) win.activate(win.confirming);
                    else win.confirming = null;
                    break;
                case Qt.Key_Escape:
                    win.confirming = null;
                    break;
                default:
                    return;
                }
                event.accepted = true;
                return;
            }

            switch (event.key) {
            case Qt.Key_Left:
                win.selected = Math.max(0, win.selected - 1);
                break;
            case Qt.Key_Right:
                win.selected = Math.min(win.actions.length - 1, win.selected + 1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter: win.activate(win.actions[win.selected]); break;
            case Qt.Key_Escape: win.dismissed(); break;
            default: return;
            }
            event.accepted = true;
        }

        Frame {
            id: powerFrame
            width: 720
            anchors.centerIn: parent
            title: "POWER"

            padTop: 18
            padSide: 18
            padBottom: 16

            Column {
                width: parent.width
                spacing: 14

                // The five tiles.
                Row {
                    visible: win.confirming === null
                    width: parent.width
                    spacing: 12

                    readonly property int tileWidth:
                        (width - (win.actions.length - 1) * 12) / win.actions.length

                    Repeater {
                        model: win.actions

                        Rectangle {
                            id: cell

                            required property int index
                            required property var modelData

                            readonly property bool active: win.selected === index
                            readonly property color hue:
                                modelData.danger ? Skin.critical : Skin.snd

                            width: parent.tileWidth
                            height: 108
                            color: active ? Skin.window : Skin.cell
                            border.width: 2
                            border.color: active ? hue : Skin.inner

                            Column {
                                anchors.centerIn: parent
                                spacing: 12

                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: cell.modelData.icon
                                    size: 24
                                    color: cell.active ? cell.hue
                                         : cell.modelData.danger ? Skin.critical
                                         : Skin.body
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: cell.modelData.name
                                    color: cell.active ? cell.hue
                                         : cell.modelData.danger ? Skin.critical
                                         : Skin.body
                                    font.family: Skin.fontLabel
                                    font.bold: cell.active
                                    font.pixelSize: 10
                                    font.letterSpacing: 10 * 0.12
                                }
                            }

                            TapHandler {
                                onTapped: {
                                    win.selected = cell.index;
                                    win.activate(cell.modelData);
                                }
                            }
                        }
                    }
                }

                // What the highlighted action does, and its real bind.
                Item {
                    visible: win.confirming === null
                    width: parent.width
                    height: noteText.implicitHeight

                    Text {
                        id: noteText
                        text: win.actions[win.selected].note
                        color: Skin.body
                        font.family: Skin.fontBody
                        font.pixelSize: 14
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.baseline: noteText.baseline
                        text: win.actions[win.selected].key !== ""
                            ? win.actions[win.selected].key : "← → · ↵ · ESC"
                        color: Skin.dim
                        font.family: Skin.fontLabel
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.14
                    }
                }

                // Confirmation: a red-framed log line inside the menu.
                Rectangle {
                    visible: win.confirming !== null
                    width: parent.width
                    height: confirmCol.implicitHeight + 38
                    color: Skin.cell
                    border.width: 2
                    border.color: Skin.critical

                    Column {
                        id: confirmCol
                        x: 20
                        y: 18
                        width: parent.width - 54
                        spacing: 12

                        Text {
                            width: parent.width
                            text: win.confirming
                                ? (win.confirming.name === "SHUT DOWN"
                                    ? "Shut down? Unsaved work will be lost."
                                    : win.confirming.name === "RESTART"
                                    ? "Restart? The machine comes right back."
                                    : "Log out? Open apps will close.")
                                : ""
                            color: Skin.text
                            font.family: Skin.fontBody
                            font.pixelSize: 16
                            wrapMode: Text.WordWrap
                        }

                        Row {
                            spacing: 10

                            Rectangle {
                                width: yesText.implicitWidth + 44
                                height: yesText.implicitHeight + 18
                                color: win.confirmYes ? Skin.window : Skin.cell
                                border.width: 2
                                border.color: win.confirmYes ? Skin.critical : Skin.inner

                                Text {
                                    id: yesText
                                    anchors.centerIn: parent
                                    text: "YES"
                                    color: Skin.critical
                                    font.family: Skin.fontLabel
                                    font.bold: win.confirmYes
                                    font.pixelSize: 12
                                }

                                TapHandler {
                                    onTapped: win.activate(win.confirming)
                                }
                            }

                            Rectangle {
                                width: noText.implicitWidth + 44
                                height: noText.implicitHeight + 18
                                color: win.confirmYes ? Skin.cell : Skin.window
                                border.width: 2
                                border.color: win.confirmYes ? Skin.inner : Skin.snd

                                Text {
                                    id: noText
                                    anchors.centerIn: parent
                                    text: "NO"
                                    color: Skin.text
                                    font.family: Skin.fontLabel
                                    font.bold: !win.confirmYes
                                    font.pixelSize: 12
                                }

                                TapHandler {
                                    onTapped: win.confirming = null
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
