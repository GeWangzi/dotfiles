// The desk todo list: a small panel on the bottom layer, above the wallpaper
// and below every window, so it is only there on an empty workspace. That is
// the intent -- it is the empty desk's one piece of furniture, not a widget
// that fights the tiling for room.
//
// Keyboard arrives on demand: a click on the panel (Hyprland resolves
// clicks to the bottom layer only where no window covers it) gives it the
// keyboard, and focusing any window takes it back. No IPC, no keybind.
//
//   type + Return   add a task
//   click a row     remove it
//
// Store is one task per line in ~/.local/state/quickshell/todo.txt, watched,
// so `echo task >> todo.txt` from a terminal shows up live.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: win

    property var tasks: []

    anchors {
        top: true
        right: true
    }
    margins.top: 48
    margins.right: 24
    implicitWidth: 300
    implicitHeight: frame.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "shell-todo"

    readonly property string storeDir:
        (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
        + "/quickshell"

    FileView {
        id: store
        path: win.storeDir + "/todo.txt"
        watchChanges: true
        printErrors: false
        onLoaded: win.tasks = text().split("\n").filter(l => l.trim().length > 0)
        onFileChanged: reload()
    }

    function save() {
        store.setText(tasks.length ? tasks.join("\n") + "\n" : "");
    }

    function add(t) {
        t = t.trim();
        if (t === "") return;
        tasks = tasks.concat([t]);
        save();
    }

    function remove(i) {
        tasks = tasks.slice(0, i).concat(tasks.slice(i + 1));
        save();
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", storeDir])

    Frame {
        id: frame
        width: parent.width
        title: "TODO"

        Column {
            width: frame.width - 2 * (frame.frameBorder + frame.padSide)
            spacing: 6

            Repeater {
                model: win.tasks

                Item {
                    required property int index
                    required property string modelData

                    width: parent.width
                    height: 22

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        elide: Text.ElideRight
                        text: parent.modelData
                        color: hover.containsMouse ? Skin.critical : Skin.body
                        font.family: Skin.fontBody
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: win.remove(parent.index)
                    }
                }
            }

            // The add line. A click here is what brings the keyboard.
            Row {
                width: parent.width
                height: 22
                spacing: 6

                TextInput {
                    id: input
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    focus: true
                    color: Skin.text
                    font.family: Skin.fontBody
                    font.pixelSize: 16
                    onAccepted: {
                        win.add(text);
                        text = "";
                    }

                    Text {
                        visible: !input.activeFocus && input.text === ""
                        text: "click to add"
                        color: Skin.dim
                        font: input.font
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: input.forceActiveFocus()
                    }
                }
            }
        }
    }
}
