// The OSD, from turn 15e of the creature-shell handoff. Bottom centre,
// framed, one 8-step meter, no interaction. Volume fills with `text`,
// brightness with `outer`, both over the `inner` track with the tick
// overlay.
//
// Dismissal is four hard opacity frames with no tween -- steps(1) is the
// design's entire animation vocabulary -- and each frame is a Timer tick,
// never a QML animation (see Blink.qml for why that matters on a surface
// that would otherwise hold the frame clock at refresh rate).
//
// The extremes name a move: volume 0 THROAT CHOP, volume max BOOMBURST,
// brightness 0 BLACK HOLE ECLIPSE, brightness max LIGHT THAT BURNS THE SKY
// (full names at the user's request). The details menu uses the same words.

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
    // content + (20px pad + 5px border) each side + 12px of soft shadow;
    // 8px above and 18px below for the shadow's downward offset.
    implicitWidth: content.implicitWidth + 74
    implicitHeight: content.implicitHeight + 60
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
    // no figure at all -- the bars are the whole readout. Extremes name a
    // move, and the brightness pair get their full names.
    readonly property string label: {
        if (mode === "vol") {
            if (SysState.volPct === 0) return "THROAT CHOP";
            if (SysState.volPct >= 100) return "BOOMBURST";
            return "VOL " + SysState.volPct + "%";
        }
        if (value === 0) return "BLACK HOLE ECLIPSE";
        if (value >= 8) return "LIGHT THAT BURNS THE SKY";
        return "BRIGHT";
    }

    Item {
        anchors.fill: parent
        opacity: osd.opacities[Math.min(osd.frame, osd.opacities.length - 1)]

        // Soft shadow, then the framed window (soft-shadows-only decision).
        Rectangle {
            x: 12
            y: 8
            width: parent.width - 24
            height: parent.height - 26
            color: Skin.window
            border.width: 5
            border.color: Skin.outer

            SoftShadow {
                z: -1
                anchors.fill: parent
            }

            Column {
                id: content
                x: 25
                y: 17
                spacing: 8

                Text {
                    text: osd.label
                    color: Skin.text
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.16
                }

                Meter {
                    blocks: osd.mode === "vol" ? 20 : 8
                    filled: osd.value
                    blockWidth: osd.mode === "vol" ? 8 : 13
                    blockHeight: 14
                    spacing: osd.mode === "vol" ? 2 : 3
                    fillColor: osd.mode === "vol" ? Skin.text : Skin.outer
                    ticks: true
                }
            }
        }
    }
}
