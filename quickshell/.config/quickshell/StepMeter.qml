// The trainable 8-step meter (turns 15d/17a). Two dresses, picked by the
// skin's `meter` variant slot: "flat" (the default) is plain equal blocks
// separated only by the gap, and "blocks" is the creature costume's chunky
// original -- shine along the top edge, a hard 2px shadow keyline, and the
// tick overlay on filled blocks. Clicking a block sets that value; clicking
// the block that IS the value steps down one, so zero stays reachable by
// mouse.

import QtQuick

Item {
    id: root

    property int steps: 8
    property int value: 0
    property color fillColor: Skin.text
    property bool outlined: false

    readonly property bool chunky: Skin.variant("meter", "flat") === "blocks"

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
                border.width: root.chunky ? 2 : 0
                border.color: Skin.shadow

                // shine
                Rectangle {
                    visible: parent.filled && Skin.shine
                    x: 2
                    y: 2
                    width: parent.width - 4
                    height: 2
                    color: "#47ffffff"
                }

                // ticks
                Repeater {
                    model: root.chunky && parent.filled
                           ? Math.floor((parent.width - 4) / 4) : 0

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
