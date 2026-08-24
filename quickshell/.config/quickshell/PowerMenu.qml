// The power menu, from turn 19a of the creature-shell handoff: four session
// actions on the move-bar frame under a CAPTURE DEVICE tab, each with its
// real keybind and one line on what happens to HP and PP. Confirmation is a
// red-framed log line with YES / NO -- not a second menu.
//
// The key hints in the cells are this machine's actual binds, not the
// design's: LOCK is SUPER+L, LOG OUT is SUPER+SHIFT+L (hyprland.lua).

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
            name: "LOCK", key: "SUPER + L", danger: false, confirm: false,
            note: "Stays awake. Moves keep their PP.",
            run: ["loginctl", "lock-session"]
        },
        {
            name: "SUSPEND", key: "CLOSE LID", danger: false, confirm: false,
            note: "Sleeps. HP holds where it is.",
            run: ["systemctl", "suspend"]
        },
        {
            name: "LOG OUT", key: "SUPER + SHIFT + L", danger: false, confirm: true,
            note: "Ends the session. Moves are cleared.",
            run: ["hyprctl", "dispatch", "exit"]
        },
        {
            name: "SHUT DOWN", key: "HOLD POWER", danger: true, confirm: true,
            note: "Full stop. Everything is released.",
            run: ["systemctl", "poweroff"]
        }
    ]

    // Reachable only through `qs ipc call power confirm RESTART` (the
    // details menu's SESSION row): not on the grid, but it confirms and
    // runs through the same flow.
    readonly property var extraActions: [
        {
            name: "RESTART", key: "", danger: false, confirm: true,
            note: "", run: ["systemctl", "reboot"]
        }
    ]

    // Open straight onto the confirm line for a named action. Unknown
    // names leave the plain grid up.
    function openConfirm(name) {
        const all = actions.concat(extraActions);
        for (let i = 0; i < all.length; i++) {
            if (all[i].name === name && all[i].confirm) {
                confirming = all[i];
                confirmYes = false;
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
    WlrLayershell.namespace: "rpg-power"

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

        // Dismiss only on a click OUTSIDE the frame -- the empty TapHandler
        // on the frame never actually swallowed taps (no exclusive grab), so
        // clicking a cell both activated it and closed the menu.
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
            case Qt.Key_Left:  win.selected = Math.floor(win.selected / 2) * 2; break;
            case Qt.Key_Right: win.selected = Math.floor(win.selected / 2) * 2 + 1; break;
            case Qt.Key_Up:    win.selected = win.selected % 2; break;
            case Qt.Key_Down:  win.selected = 2 + win.selected % 2; break;
            case Qt.Key_Return:
            case Qt.Key_Enter: win.activate(win.actions[win.selected]); break;
            case Qt.Key_Escape: win.dismissed(); break;
            default: return;
            }
            event.accepted = true;
        }

        Frame {
            id: powerFrame
            width: 640
            anchors.centerIn: parent
            title: Skin.ballWord

            padTop: 24
            padSide: 18
            padBottom: 18

            Column {
                width: parent.width
                spacing: 14

                // Header row.
                Item {
                    width: parent.width
                    height: headText.implicitHeight

                    Text {
                        id: headText
                        text: "RETURN " + Skin.species + " TO THE DEVICE"
                        color: Skin.text
                        font.family: Skin.fontLabel
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.baseline: headText.baseline
                        text: "SUPER + ESC"
                        color: Skin.dim
                        font.family: Skin.fontLabel
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.14
                    }
                }

                // 2x2 action grid.
                Grid {
                    visible: win.confirming === null
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 12
                    width: parent.width

                    readonly property int cellWidth: (width - 12) / 2

                    Repeater {
                        model: win.actions

                        Rectangle {
                            id: cell

                            required property int index
                            required property var modelData

                            readonly property bool active: win.selected === index

                            width: parent.cellWidth
                            height: 96
                            color: Skin.cell
                            border.width: 3
                            // Danger reads in the red name; the border only
                            // goes red when the cell is highlighted, like the
                            // YES button below -- a permanently red border
                            // meant SHUT DOWN never showed selection at all.
                            border.color: active
                                ? (modelData.danger ? Skin.critical : Skin.outer)
                                : Skin.inner

                            Column {
                                x: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 28
                                spacing: 6

                                Text {
                                    text: cell.modelData.name
                                    color: cell.modelData.danger ? Skin.critical : Skin.text
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 14
                                }

                                Text {
                                    text: cell.modelData.key
                                    color: Skin.dim
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 10
                                    font.letterSpacing: 10 * 0.12
                                }

                                Text {
                                    width: parent.width
                                    text: cell.modelData.note
                                    color: Skin.body
                                    font.family: Skin.fontBody
                                    font.pixelSize: 16
                                    wrapMode: Text.WordWrap
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

                // Confirmation: a red-framed log line inside the menu.
                Rectangle {
                    visible: win.confirming !== null
                    width: parent.width
                    height: confirmCol.implicitHeight + 38
                    color: Skin.window
                    border.width: 5
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
                                    ? "Shut down " + Skin.species + "? Everything running is released."
                                    : win.confirming.name === "RESTART"
                                    ? "Restart " + Skin.species + "? Everything is released, then it comes back."
                                    : "End the session? Every move loses its PP.")
                                : ""
                            color: Skin.text
                            font.family: Skin.fontBody
                            font.pixelSize: 18
                            wrapMode: Text.WordWrap
                        }

                        Row {
                            spacing: 10

                            Rectangle {
                                width: yesText.implicitWidth + 44
                                height: yesText.implicitHeight + 18
                                color: Skin.cell
                                border.width: 3
                                border.color: win.confirmYes ? Skin.critical : Skin.inner

                                Text {
                                    id: yesText
                                    anchors.centerIn: parent
                                    text: "YES"
                                    color: Skin.critical
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 12
                                }

                                TapHandler {
                                    onTapped: win.activate(win.confirming)
                                }
                            }

                            Rectangle {
                                width: noText.implicitWidth + 44
                                height: noText.implicitHeight + 18
                                color: Skin.cell
                                border.width: 3
                                border.color: win.confirmYes ? Skin.inner : Skin.outer

                                Text {
                                    id: noText
                                    anchors.centerIn: parent
                                    text: "NO"
                                    color: Skin.text
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 12
                                }

                                TapHandler {
                                    onTapped: win.confirming = null
                                }
                            }
                        }
                    }

                    Blink {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        periodMs: 400
                        width: confirmAdvance.implicitWidth
                        height: confirmAdvance.implicitHeight

                        Text {
                            id: confirmAdvance
                            text: Skin.glyphMore
                            color: Skin.critical
                            font.family: Skin.fontLabel
                            font.pixelSize: 14
                        }
                    }
                }
            }
        }
    }
}
