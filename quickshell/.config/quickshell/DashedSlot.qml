// A dashed placeholder slot: 3px dashed `inner` with a dim Silkscreen label,
// exactly what the design ships where original sprite art is still owed.
// QML has no dashed border, so the dashes are short rectangles marched
// around the edge.

import QtQuick

Item {
    id: root

    property string label: "SPRITE"

    readonly property int dash: 9
    readonly property int gap: 6
    readonly property int stroke: 3

    Row {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.gap
        Repeater {
            model: Math.floor((root.width + root.gap) / (root.dash + root.gap))
            Rectangle { width: root.dash; height: root.stroke; color: Skin.inner }
        }
    }

    Row {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.gap
        Repeater {
            model: Math.floor((root.width + root.gap) / (root.dash + root.gap))
            Rectangle { width: root.dash; height: root.stroke; color: Skin.inner }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.gap
        Repeater {
            model: Math.floor((root.height + root.gap) / (root.dash + root.gap))
            Rectangle { width: root.stroke; height: root.dash; color: Skin.inner }
        }
    }

    Column {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.gap
        Repeater {
            model: Math.floor((root.height + root.gap) / (root.dash + root.gap))
            Rectangle { width: root.stroke; height: root.dash; color: Skin.inner }
        }
    }

    Text {
        anchors.centerIn: parent
        text: root.label
        color: Skin.dim
        font.family: Skin.fontLabel
        font.pixelSize: 10
        font.letterSpacing: 10 * 0.12
    }
}
