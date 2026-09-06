// The text caret: a 2px rule in the text colour, blinking on the skin's
// period. A standard caret, not a block -- the block cursor went 2026-09-06
// (user call: "just the normal cursor").

import QtQuick

Blink {
    // The line height of the text it sits beside.
    property int lineHeight: 17

    width: 2
    height: lineHeight

    Rectangle {
        anchors.fill: parent
        color: Skin.text
    }
}
