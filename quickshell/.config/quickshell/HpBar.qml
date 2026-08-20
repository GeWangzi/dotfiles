// A continuous meter with the design's tick overlay:
//
//     background: <track>;
//     .fill { width: n%; background: <fill>;
//             background-image: repeating-linear-gradient(90deg,
//                 rgba(0,0,0,.34) 0 1px, transparent 1px 4px); }
//
// Used at 150x9 and 116x9 (own HP), 78x7 (foe HP) on the status bar, and at
// larger sizes on the wallpaper plates and the details menu. The ticks are
// 1px columns every 4px, drawn only over the filled part, exactly like the
// gradient. Distinct from Meter.qml, which is the older block meter -- the
// creature shell uses continuous bars everywhere.

import QtQuick

Rectangle {
    id: root

    // 0.0 - 1.0
    property real fraction: 0
    property color fillColor: Skin.accent

    // At HP critical only the remaining segment flashes (turn 19c) -- the
    // track stays put and there is no chip. 0.4s is the alarm blink rate.
    // Timer-toggled, never a QML animation; see Blink.qml for why.
    property bool alarm: false

    implicitWidth: 150
    implicitHeight: 9
    color: Skin.inner

    property bool alarmPhase: true

    Timer {
        interval: 200
        running: root.alarm && root.visible
        repeat: true
        onTriggered: root.alarmPhase = !root.alarmPhase
    }
    onAlarmChanged: alarmPhase = true

    Rectangle {
        id: fill
        visible: !root.alarm || root.alarmPhase
        width: Math.round(root.width * Math.max(0, Math.min(1, root.fraction)))
        height: parent.height
        color: root.fillColor

        Repeater {
            model: Math.floor(fill.width / 4)

            Rectangle {
                required property int index
                x: index * 4
                width: 1
                height: fill.height
                color: "#57000000"   // rgba(0,0,0,.34)
            }
        }
    }
}
