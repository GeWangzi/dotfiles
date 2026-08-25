// The drop shadow behind every framed surface. Console dress (2026-08-24):
// one hard offset slab in the skin's `shadow` token -- box-shadow
// 8px 8px 0 <shadow>, no blur, no rings. This replaces the 2026-08-20
// soft-shadow stack (three translucent rectangles), which lives in git
// history; the file keeps its name so the call sites did not have to move.
//
// Size it to the face it shadows and put it behind (declare it before the
// face, or give it z: -1 as a child).

import QtQuick

Item {
    id: root

    // Kept for call-site compatibility; the console drop is symmetric so the
    // one value offsets both axes.
    property int offsetY: 8

    Rectangle {
        x: root.offsetY
        y: root.offsetY
        width: root.width
        height: root.height
        radius: Skin.radius
        color: Skin.shadow
    }
}
