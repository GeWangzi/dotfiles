// The 8- or 20-step meter. Equal blocks separated only by the gap; filled
// blocks take `fillColor`, empty ones the `inner` track. Clicking a block
// sets that value; clicking the block that IS the value steps down one, so
// zero stays reachable by mouse. `outlined` draws the focus ring.

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
        border.color: Skin.snd
    }
}
