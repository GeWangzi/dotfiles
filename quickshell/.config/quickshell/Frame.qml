// The frame motif, reused by the launcher, the notification toast, the power
// menu, the calendar page and the control center. Console dress (2026-08-24):
//
//     border: 2px solid <inner>;
//     background: <bg>;
//
// plus a titlebar STRIP inside the top edge -- <cell> fill, a 2px rule under
// it. No shadow (hard shadows went 2026-08-25, soft ones before that).

import QtQuick

Item {
    id: root

    // Titlebar text. Empty means no titlebar strip.
    property string title: ""

    // Content goes inside the border, below the titlebar, and the padding.
    default property alias content: body.data

    property int padTop: 36
    property int padSide: 30
    property int padBottom: 26

    readonly property int frameBorder: 2
    // The toast variant recolors the border for critical urgency.
    property color borderColor: Skin.inner

    readonly property int stripHeight: title !== "" ? 28 : 0

    // childrenRect rather than implicitWidth/Height, because `body` is a plain
    // Item and a plain Item's implicit size is zero no matter what is inside
    // it -- only childrenRect measures the content.
    implicitWidth: body.childrenRect.width + 2 * (frameBorder + padSide)
    implicitHeight: body.childrenRect.height + 2 * frameBorder + stripHeight
                    + padTop + padBottom

    Rectangle {
        anchors.fill: parent
        color: Skin.bg
        radius: Skin.radius
        border.width: root.frameBorder
        border.color: root.borderColor
    }

    // Titlebar strip: inside the border, full width, ruled off underneath.
    Rectangle {
        visible: root.title !== ""
        x: root.frameBorder
        y: root.frameBorder
        width: root.width - 2 * root.frameBorder
        height: root.stripHeight

        color: Skin.cell

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: root.frameBorder
            color: root.borderColor
        }

        Text {
            id: stripText
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            color: Skin.text
            font.family: Skin.fontLabel
            font.bold: true
            font.pixelSize: 12
            font.letterSpacing: 12 * 0.10
        }
    }

    Item {
        id: body
        x: root.frameBorder + root.padSide
        y: root.frameBorder + root.stripHeight + root.padTop
        width: root.width - 2 * (root.frameBorder + root.padSide)
        // Height follows the content rather than being derived back from
        // root.height, which would be a binding loop against implicitHeight.
        height: childrenRect.height
    }
}
