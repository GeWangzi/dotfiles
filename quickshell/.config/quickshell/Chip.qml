// A status chip. Two shapes, and the shape carries meaning (handoff turn 20):
//
//   filled          a status condition -- something limiting the machine.
//                   Solid hue, `shadow`-coloured text.
//   dashed outline  a field effect the machine raised itself (SUB).
//                   Accent-coloured text, transparent fill.
//
// A chip renders only when the underlying state is real; that is the caller's
// job, not this component's.

import QtQuick

Rectangle {
    id: root

    property string label: ""
    property color hue: Skin.accent
    property bool fieldEffect: false

    implicitWidth: chipText.implicitWidth + 12
    implicitHeight: chipText.implicitHeight + 4

    color: fieldEffect ? "transparent" : hue

    // QML has no dashed border; four edge rows of short dashes would be
    // overkill at this size, so the field-effect outline is drawn as a 2px
    // rule interrupted by the background -- visually a coarse dash.
    Row {
        visible: root.fieldEffect
        anchors.top: parent.top
        spacing: 3
        Repeater {
            model: Math.ceil(root.width / 7)
            Rectangle { width: 4; height: 2; color: root.hue }
        }
    }
    Row {
        visible: root.fieldEffect
        anchors.bottom: parent.bottom
        spacing: 3
        Repeater {
            model: Math.ceil(root.width / 7)
            Rectangle { width: 4; height: 2; color: root.hue }
        }
    }
    Column {
        visible: root.fieldEffect
        anchors.left: parent.left
        spacing: 3
        Repeater {
            model: Math.ceil(root.height / 7)
            Rectangle { width: 2; height: 4; color: root.hue }
        }
    }
    Column {
        visible: root.fieldEffect
        anchors.right: parent.right
        spacing: 3
        Repeater {
            model: Math.ceil(root.height / 7)
            Rectangle { width: 2; height: 4; color: root.hue }
        }
    }

    Text {
        id: chipText
        anchors.centerIn: parent
        text: root.label
        color: root.fieldEffect ? root.hue : Skin.shadow
        font.family: Skin.fontLabel
        font.pixelSize: 10   // 9 in the design; even for the pixel grid
        font.letterSpacing: 10 * 0.16
    }
}
