// Wallpaper widget text. The hard pixel glyph shadow (a second Text painted
// offset behind this one, from the 15c unframed treatment) was removed with
// the rest of the hard shadows (user call, 2026-08-25); it is in git history
// if the clock ever stops reading against a bright wallpaper.

import QtQuick

Item {
    id: root

    property string text: ""
    property int size: 10
    property real tracking: 0
    property color color: Skin.text
    property string family: Skin.fontLabel
    // Kept for call-site compatibility; nothing is offset any more.
    property int shadowOffset: 3
    property int maxWidth: 0

    implicitWidth: fg.implicitWidth
    implicitHeight: fg.implicitHeight

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
