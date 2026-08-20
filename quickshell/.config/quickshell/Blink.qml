// A blinking container. Wrap anything that needs the design's cursor blink.
//
// Blink is the design's entire animation vocabulary -- no easing, no
// transforms, no sliding -- and it is deliberately implemented here as a Timer
// toggling a boolean rather than as a QML animation on opacity.
//
// The reason is power, not style. An active QML animation drives the scene
// graph's frame clock at the monitor refresh rate for as long as it runs, so a
// cursor that changes twice a second would repaint sixty times a second and
// hold the GPU out of its idle state for as long as the surface is visible.
// A Timer wakes twice a second and repaints twice a second. The design calls
// for steps(1), which is discrete by definition, so nothing is lost.
//
// Never replace this with a NumberAnimation or a Behavior.

import QtQuick

Item {
    id: root

    // Full on-off cycle length. Defaults to the active skin's blink token.
    property int periodMs: Skin.blinkMs

    // Set false to hold the content visible without tearing down the item.
    property bool blinking: true

    default property alias content: holder.data

    Item {
        id: holder
        anchors.fill: parent
        opacity: (!root.blinking || root.phase) ? 1 : 0
    }

    property bool phase: true

    Timer {
        // Half the period, because one full cycle is on then off.
        interval: Math.max(1, Math.round(root.periodMs / 2))
        running: root.blinking && root.visible
        repeat: true
        onTriggered: root.phase = !root.phase
    }

    // Always come back visible, so a surface that is hidden mid-blink does not
    // reappear with its cursor missing.
    onVisibleChanged: if (visible) phase = true
}
