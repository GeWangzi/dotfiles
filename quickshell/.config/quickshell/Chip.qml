// A tag chip: a solid hue with `bg`-coloured text. A chip renders only when
// the underlying state is real; that is the caller's job, not this
// component's.

import QtQuick

Rectangle {
    id: root

    property string label: ""
    property color hue: Skin.accent

    implicitWidth: chipText.implicitWidth + 12
    implicitHeight: chipText.implicitHeight + 4

    color: hue

    Text {
        id: chipText
        anchors.centerIn: parent
        text: root.label
        color: Skin.bg
        font.family: Skin.fontLabel
        font.pixelSize: 10
        font.letterSpacing: 10 * 0.16
    }
}
