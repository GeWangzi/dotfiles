// Wallpaper widget text: the design's unframed treatment (15c, kept by 16a)
// gives every glyph a hard pixel drop shadow -- text-shadow: 3-4px 3-4px 0
// rgba(0,0,0,.92) -- which QML has no property for, so it is a second Text
// painted offset behind the first. No blur: the shadow is a hard copy.

import QtQuick

Item {
    id: root

    property string text: ""
    property int size: 10
    property real tracking: 0
    property color color: Skin.text
    property string family: Skin.fontLabel
    property int shadowOffset: 3
    property int maxWidth: 0

    implicitWidth: fg.implicitWidth
    implicitHeight: fg.implicitHeight

    Text {
        x: root.shadowOffset
        y: root.shadowOffset
        width: root.maxWidth > 0 ? root.maxWidth : undefined
        text: root.text
        color: "#eb000000"
        font.family: root.family
        font.pixelSize: root.size
        font.letterSpacing: root.tracking
        elide: root.maxWidth > 0 ? Text.ElideRight : Text.ElideNone
    }

    Text {
        id: fg
        width: root.maxWidth > 0 ? root.maxWidth : undefined
        text: root.text
        color: root.color
        font.family: root.family
        font.pixelSize: root.size
        font.letterSpacing: root.tracking
        elide: root.maxWidth > 0 ? Text.ElideRight : Text.ElideNone
    }
}
