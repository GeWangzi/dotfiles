// The frame motif, which the design reuses verbatim on the launcher, the
// notification toast, the lock screen's save slot and the control center:
//
//     border: 5px solid <outer>;
//     border-radius: <radius>;
//     background: <window>;
//
// plus a soft drop shadow (SoftShadow.qml). The handoff's hard shadow-token
// halo and hard offset drop were retired 2026-08-20: soft shadows only,
// around every window border.
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
    // The toast variant recolors the border for critical urgency.
    property color borderColor: Skin.outer

    // childrenRect rather than implicitWidth/Height, because `body` is a plain
    // Item and a plain Item's implicit size is zero no matter what is inside
    // it -- only childrenRect measures the content. Getting this wrong makes
    // the frame collapse to a sliver while its contents draw straight through
    // the border, since nothing here clips.
    implicitWidth: body.childrenRect.width + 2 * (frameBorder + padSide)
    implicitHeight: body.childrenRect.height + 2 * frameBorder + padTop + padBottom

    // Soft shadows only around window borders (design decision 2026-08-20);
    // the hard halo + hard drop this replaced live in git history.
    SoftShadow {
        anchors.fill: parent
    }

    Rectangle {
        anchors.fill: parent
        color: Skin.window
        radius: Skin.radius
        border.width: root.frameBorder
        border.color: root.borderColor
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

    // Title tab: left 22px, sitting flush ON the frame's top edge like a
    // folder tab -- nothing pokes down past the border (user call,
    // 2026-08-20). Its hard shadow ring went with the halo.
    Item {
        visible: root.title !== ""
        x: 22
        y: -height
        implicitWidth: tabText.implicitWidth + 2 * 12
        implicitHeight: tabText.implicitHeight + 2 * 5
        width: implicitWidth
        height: implicitHeight

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
            font.family: Skin.fontLabel
            // 11-12px in the design; 12 because odd logical sizes land on half
            // physical pixels at this monitor's 1.5 scale and a pixel font
            // smears when they do. See fonts/README.md.
            font.pixelSize: 12
            font.letterSpacing: 12 * 0.18
        }
    }
}
