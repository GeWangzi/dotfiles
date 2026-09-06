// The OSD, from turn 15e of the creature-shell handoff, in the Console dress:
// bottom centre, one panel, an icon naming the channel, the block meter
// filling with `accent` over the `inner` track, and the volume figure. No
// interaction.
//
// Dismissal is four hard opacity frames with no tween -- steps(1) is the
// design's entire animation vocabulary -- and each frame is a Timer tick,
// never a QML animation (see Blink.qml for why that matters on a surface
// that would otherwise hold the frame clock at refresh rate).
//
// The extremes get a name: plain by default, and the creature voice names a
// move through the osd_* lexicon keys. The details menu uses the same words.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: osd

    // "vol" or "bright"
    property string mode: "vol"

    // 1 -> 0.66 -> 0.33 -> hidden. Index into OPACITIES.
    property int frame: 0
    readonly property var opacities: [1.0, 0.66, 0.33]

    // Ignore the value changes that fire while state syncs at startup.
    property bool armed: false

    visible: false

    anchors.bottom: true
    margins.bottom: 64
    // content + 24px pad + 2px border each side.
    implicitWidth: content.implicitWidth + 2 * 26
    implicitHeight: content.implicitHeight + 2 * 18
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "rpg-osd"

    Timer {
        interval: 2000
        running: true
        onTriggered: osd.armed = true
    }

    function show(which) {
        if (!armed) return;
        mode = which;
        frame = 0;
        holdTimer.restart();
        fadeTimer.stop();
        visible = true;
    }

    Connections {
        target: SysState

        function onVolPctChanged(): void { osd.show("vol"); }
        function onBright8Changed(): void { osd.show("bright"); }
    }

    // Hold fully visible, then step down three hard frames.
    Timer {
        id: holdTimer
        interval: 1200
        onTriggered: fadeTimer.start()
    }

    Timer {
        id: fadeTimer
        interval: 120
        repeat: true
        onTriggered: {
            osd.frame++;
            if (osd.frame >= osd.opacities.length) {
                stop();
                osd.visible = false;
                osd.frame = 0;
            }
        }
    }

    readonly property int value: mode === "vol" ? SysState.vol20 : SysState.bright8

    // Volume reads the real percent (keys move it in 5s); brightness shows
    // no figure at all -- the bars are the whole readout (user decision).
    // MUTE is the one word the panel keeps: an empty meter alone cannot say
    // whether the sink is muted or just quiet.
    readonly property string figure: {
        if (mode !== "vol") return "";
        if (SysState.muted) return "MUTE";
        return "" + SysState.volPct;
    }

    Item {
        anchors.fill: parent
        opacity: osd.opacities[Math.min(osd.frame, osd.opacities.length - 1)]

        // Console panel: 2px rule, one row.
        Rectangle {
            anchors.fill: parent
            color: Skin.bg
            border.width: 2
            border.color: Skin.inner

            Row {
                id: content
                anchors.centerIn: parent
                spacing: 14

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: osd.mode === "vol" ? "vol" : "sun"
                    size: 18
                    color: osd.mode === "vol" && SysState.muted
                        ? Skin.critical : Skin.body
                }

                // Same geometry as the details menu's meters: 20 steps of
                // 8px for volume, 8 steps of 13px for brightness, 4px gaps.
                StepMeter {
                    anchors.verticalCenter: parent.verticalCenter
                    steps: osd.mode === "vol" ? 20 : 8
                    width: steps * (osd.mode === "vol" ? 8 : 13) + (steps - 1) * 4
                    height: 12
                    value: osd.value
                    fillColor: Skin.accent
                }

                Text {
                    visible: text !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: osd.figure
                    color: osd.mode === "vol" && SysState.muted
                        ? Skin.critical : Skin.text
                    font.family: Skin.fontLabel
                    font.bold: true
                    font.pixelSize: 14
                }
            }
        }
    }
}
