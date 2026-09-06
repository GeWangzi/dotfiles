// A stroke icon, drawn as SVG path data so it recolors with the skin and
// scales without shipping image assets. The set is the Console dress's icon
// language: 1.5px round-capped strokes on a 24px grid, the same family the
// design handoff drew for the bar, the OSD, the lock and the power menu.
//
// Usage: Icon { name: "wifi"; size: 14; color: Skin.dim }
//
// An unknown name draws nothing rather than erroring, so a surface can bind
// a name it is not sure of.

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property string name: ""
    property int size: 16
    property color color: Skin.body
    property real thickness: 1.5

    // Path data on a 24x24 grid. `fill` entries are painted solid (the wifi
    // dot); everything else strokes.
    readonly property var table: ({
        search: { d: "M17 10.5A6.5 6.5 0 1 1 4 10.5A6.5 6.5 0 1 1 17 10.5M15.4 15.4L20.5 20.5" },
        wifi:   { d: "M2.2 9.3a14.3 14.3 0 0 1 19.6 0M5.7 13.2a9 9 0 0 1 12.6 0M9.2 17a4.2 4.2 0 0 1 5.6 0",
                  fill: "M12 18.8a1.5 1.5 0 1 0 0 3a1.5 1.5 0 0 0 0-3" },
        vol:    { d: "M3 8.25h7.5l4.5-4.5v16.5l-4.5-4.5H3zM18.75 9a4.5 4.5 0 0 1 0 6" },
        sun:    { d: "M16.8 12A4.8 4.8 0 1 1 7.2 12A4.8 4.8 0 1 1 16.8 12M12 1.8v2.7M12 19.5v2.7M1.8 12h2.7M19.5 12h2.7M4.8 4.8l1.9 1.9M17.3 17.3l1.9 1.9M19.2 4.8l-1.9 1.9M6.7 17.3l-1.9 1.9" },
        lock:   { d: "M5 11h14v9H5zM8 11V7a4 4 0 0 1 8 0v4" },
        logout: { d: "M14 4H7a1.5 1.5 0 0 0-1.5 1.5v13A1.5 1.5 0 0 0 7 20h7M11 12h9M17 8.5L20.5 12L17 15.5" },
        moon:   { d: "M20 13.2A8.2 8.2 0 1 1 10.8 4a6.6 6.6 0 0 0 9.2 9.2z" },
        reboot: { d: "M4.5 12a7.5 7.5 0 1 0 2.2-5.3M6.5 2.8v4h4" },
        power:  { d: "M12 3v8M6.6 6.2a7.5 7.5 0 1 0 10.8 0" },
        bt:     { d: "M7 7.5L16.5 16.5L12 20.5V3.5L16.5 7.5L7 16.5" },
        globe:  { d: "M21.5 12A9.5 9.5 0 1 1 2.5 12A9.5 9.5 0 1 1 21.5 12M2.5 12h19M12 2.5c-2.9 2.9-2.9 16.1 0 19M12 2.5c2.9 2.9 2.9 16.1 0 19" },
        bellOff:{ d: "M5.5 17.5V11a6.5 6.5 0 0 1 13 0v6.5l2 2h-17zM9.5 19.5a2.5 2.5 0 0 0 5 0M3.5 3.5l17 17" }
    })

    readonly property var entry: table[name] || null

    width: size
    height: size

    Shape {
        width: 24
        height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.color
            // The transform scales the stroke too; divide so the visual
            // weight stays `thickness` at every size.
            strokeWidth: root.thickness * 24 / root.size
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg { path: root.entry ? root.entry.d : "" }
        }

        ShapePath {
            strokeColor: "transparent"
            fillColor: root.entry && root.entry.fill ? root.color : "transparent"

            PathSvg { path: root.entry && root.entry.fill ? root.entry.fill : "" }
        }
    }
}
