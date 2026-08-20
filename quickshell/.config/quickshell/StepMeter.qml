// The trainable 8-step meter (turns 15d/17a): equal blocks with a shine
// along the top edge (inset 0 2px 0 0 rgba(255,255,255,.28)), a hard 2px
// shadow keyline, and the tick overlay on filled blocks. Clicking a block
// sets that value; clicking the block that IS the value steps down one, so
// zero stays reachable by mouse.

import QtQuick

Item {
    id: root

    property int steps: 8
    property int value: 0
    property color fillColor: Skin.text
    property bool outlined: false

    signal stepClicked(int n)

    readonly property real blockWidth: (width - (steps - 1) * 4) / steps

    Row {
        anchors.fill: parent
        spacing: 4

        Repeater {
            model: root.steps

            Rectangle {
                required property int index

                readonly property bool filled: index < root.value

                width: root.blockWidth
                height: root.height
                color: filled ? root.fillColor : Skin.inner
                border.width: 2
                border.color: Skin.shadow

                // shine
                Rectangle {
                    visible: parent.filled
                    x: 2
                    y: 2
                    width: parent.width - 4
                    height: 2
                    color: "#47ffffff"
                }

                // ticks
                Repeater {
                    model: parent.filled ? Math.floor((parent.width - 4) / 4) : 0

                    Rectangle {
                        required property int index
                        x: 2 + index * 4
                        y: 2
                        width: 1
                        height: parent.height - 4
                        color: "#57000000"
                    }
                }

                TapHandler {
                    onTapped: root.stepClicked(
                        parent.index + 1 === root.value ? parent.index : parent.index + 1)
                }
            }
        }
    }

    Rectangle {
        visible: root.outlined
        anchors.fill: parent
        anchors.margins: -4
        color: "transparent"
        border.width: 2
        border.color: Skin.outline
    }
}
