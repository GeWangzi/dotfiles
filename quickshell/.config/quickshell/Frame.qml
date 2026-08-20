// The frame motif, which the design reuses verbatim on the launcher, the
// notification toast, the lock screen's save slot and the control center:
//
//     border: 5px solid <outer>;
//     box-shadow: 0 0 0 5px <shadow>, 0 10px 0 5px rgba(0,0,0,0.5);
//     border-radius: <radius>;
//     background: <window>;
//
// CSS box-shadow with a spread and no blur is just a larger rectangle behind
// the element, so each of the two shadows is one Rectangle here. They are
// stacked in reverse: CSS paints the first shadow on top of the second, so the
// halo is declared after the drop shadow and covers it where they overlap.
//
// The title tab overhangs the top-left corner and is the reason this is an
// Item with unclipped children rather than a plain Rectangle.

import QtQuick

Item {
    id: root

    // Tab text. Empty means no tab.
    property string title: ""

    // Content goes inside the border and the padding.
    default property alias content: body.data

    property int padTop: 36
    property int padSide: 30
    property int padBottom: 26

    readonly property int frameBorder: 5
    readonly property int spread: 5
    readonly property int dropOffset: 10

    // childrenRect rather than implicitWidth/Height, because `body` is a plain
    // Item and a plain Item's implicit size is zero no matter what is inside
    // it -- only childrenRect measures the content. Getting this wrong makes
    // the frame collapse to a sliver while its contents draw straight through
    // the border, since nothing here clips.
    implicitWidth: body.childrenRect.width + 2 * (frameBorder + padSide)
    implicitHeight: body.childrenRect.height + 2 * frameBorder + padTop + padBottom

    // box-shadow 2: 0 10px 0 5px rgba(0,0,0,0.5)
    Rectangle {
        x: -root.spread
        y: -root.spread + root.dropOffset
        width: root.width + 2 * root.spread
        height: root.height + 2 * root.spread
        radius: Skin.radius
        color: "#80000000"
    }

    // box-shadow 1: 0 0 0 5px <shadow>
    Rectangle {
        x: -root.spread
        y: -root.spread
        width: root.width + 2 * root.spread
        height: root.height + 2 * root.spread
        radius: Skin.radius
        color: Skin.shadow
    }

    Rectangle {
        anchors.fill: parent
        color: Skin.window
        radius: Skin.radius
        border.width: root.frameBorder
        border.color: Skin.outer
    }

    Item {
        id: body
        x: root.frameBorder + root.padSide
        y: root.frameBorder + root.padTop
        width: root.width - 2 * (root.frameBorder + root.padSide)
        // Height is left to follow the content rather than being derived back
        // from root.height, which would be a binding loop against the
        // implicitHeight above.
        height: childrenRect.height
    }

    // Title tab: top -19px, left 22px, filled in `outer` with `window` text,
    // and its own 5px shadow ring.
    Item {
        visible: root.title !== ""
        x: 22
        y: -19
        implicitWidth: tabText.implicitWidth + 2 * 12
        implicitHeight: tabText.implicitHeight + 2 * 5
        width: implicitWidth
        height: implicitHeight

        Rectangle {
            x: -root.spread
            y: -root.spread
            width: parent.width + 2 * root.spread
            height: parent.height + 2 * root.spread
            radius: Skin.radius
            color: Skin.shadow
        }

        Rectangle {
            anchors.fill: parent
            color: Skin.outer
            radius: Skin.radius
        }

        Text {
            id: tabText
            anchors.centerIn: parent
            text: root.title
            color: Skin.window
            font.family: "Silkscreen"
            // 11-12px in the design; 12 because odd logical sizes land on half
            // physical pixels at this monitor's 1.5 scale and a pixel font
            // smears when they do. See fonts/README.md.
            font.pixelSize: 12
            font.letterSpacing: 12 * 0.18
        }
    }
}
