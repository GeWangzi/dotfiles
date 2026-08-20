// A 7x7 pixel glyph drawn as a grid of squares, from the design's SUN / MOON
// maps. The bar's day/night indicator is the only user today; the maps are
// data so a new glyph is a new string list, not a new component.

import QtQuick

Grid {
    id: root

    // Seven strings of seven characters; '#' is a lit cell.
    property var map: []
    property color color: Skin.accent
    property int cellSize: 3

    columns: 7
    rows: 7

    Repeater {
        model: 49

        Rectangle {
            required property int index
            width: root.cellSize
            height: root.cellSize
            color: {
                const row = root.map[Math.floor(index / 7)];
                return (row && row.charAt(index % 7) === "#")
                    ? root.color : "transparent";
            }
        }
    }
}
