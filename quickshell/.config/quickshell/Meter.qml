// A block meter: N rectangles, the first `filled` of them in the fill colour
// and the rest in `inner`, which is what the design's `inner` token is for.
//
// Used by the launcher's MEM row, and by the status bar's HP bar, the control
// center's brightness, volume, CPU, MEM, party and battery rows when those
// surfaces arrive -- so keep it general.

import QtQuick

Row {
    id: root

    property int blocks: 10
    property int filled: 0

    property int blockWidth: 13
    property int blockHeight: 10
    spacing: 2

    property color fillColor: Skin.accent
    property color emptyColor: Skin.inner

    // Dream Land asks for a highlight along the top edge of a filled block.
    // The design writes it as `inset 0 2px 0 0 rgba(255,255,255,0.55)`, which
    // QML cannot express as a shadow, so it is drawn as an overlay strip.
    property bool shine: Skin.shine

    // The creature shell replaces shine with the tick overlay every meter in
    // that design carries: 1px columns of rgba(0,0,0,.34) every 4px, over
    // the filled blocks only.
    property bool ticks: false

    Repeater {
        model: root.blocks

        Rectangle {
            required property int index

            width: root.blockWidth
            height: root.blockHeight
            color: index < root.filled ? root.fillColor : root.emptyColor

            Rectangle {
                visible: root.shine && index < root.filled
                width: parent.width
                height: 2
                color: "#8cffffff"
            }

            Repeater {
                model: (root.ticks && index < root.filled)
                    ? Math.floor(root.blockWidth / 4) : 0

                Rectangle {
                    required property int index
                    x: index * 4
                    width: 1
                    height: root.blockHeight
                    color: "#57000000"
                }
            }
        }
    }
}
