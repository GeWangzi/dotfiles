// The battery glyph: outline, terminal nub, and a body that fills with the
// real charge fraction -- the icon itself is a meter, which is why it is not
// in Icon.qml's static path table. Plain rectangles, no Shape.

import QtQuick

Item {
    id: root

    // 0.0 - 1.0
    property real fraction: 1
    property color color: Skin.body
    property color fillColor: color

    implicitWidth: 19
    implicitHeight: 12

    Rectangle {
        x: 0
        width: parent.width - 3
        height: parent.height
        color: "transparent"
        border.width: 1
        border.color: root.color
    }

    Rectangle {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: 5
        color: root.color
    }

    Rectangle {
        x: 2
        y: 2
        width: Math.round((parent.width - 7) * Math.max(0, Math.min(1, root.fraction)))
        height: parent.height - 4
        color: root.fillColor
    }
}
