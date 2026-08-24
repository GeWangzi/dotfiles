// The desktop wallpaper, from turn 16a of the creature-shell handoff: the
// battle field IS the wallpaper. Foe plate top right, ally plate bottom
// right, two sprite slots, and the unframed clock top left with hard pixel
// drop shadows. The design's stat rows and now-playing widget were removed
// at the user's request (2026-08-19) -- the clock (plus the ROUTE line) is
// the whole widget stack.
//
// This surface replaces hyprpaper: it owns the background layer and paints
// the field itself. Each workspace is its own route: workspace n draws
// assets/bg-<n>.png (sliced from the user's background sheet, nearest-
// neighbour upscaled), and the clock carries a ROUTE <n> line so a bare
// workspace is tellable at a glance. The battle backgrounds made the base
// pads redundant, so sprites stand on the art itself. A missing background
// falls back to flat `cell`.
//
// Sprites are personal-use art in the gitignored assets/ folder:
//
//   assets/ally-back.gif    the machine's creature, always the wallpaper
//                           sprite (paused frame when covered or on
//                           battery). Plays ONLY while the focused
//                           workspace is bare AND the machine is on wall
//                           power -- an animation nobody can see, or one
//                           that spends battery, is exactly the wakeup this
//                           shell exists to avoid.
//   assets/ally-front.png   still fallback if the gif is missing; also the
//                           details-menu portrait.
//
// Missing files degrade to the design's dashed placeholder slots.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: wall

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "rpg-field"

    // Bare desktop: no window on the focused workspace. Event-driven from
    // the compositor. This must read the toplevel's `workspace` property,
    // not lastIpcObject.workspace: lastIpcObject only updates on a full
    // client refetch, so SUPER+SHIFT+number (movetoworkspace) left the old
    // workspace id behind and the animations kept judging stale data.
    readonly property bool bare: {
        const ws = Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace
            ? Hyprland.focusedMonitor.activeWorkspace.id : -1;
        const tops = Hyprland.toplevels.values;
        for (let i = 0; i < tops.length; i++) {
            const tws = tops[i].workspace;
            if (tws && tws.id === ws) return false;
        }
        return true;
    }

    readonly property string assetDir: Quickshell.env("HOME") + "/.config/quickshell/assets/"

    // Workspace id, wrapped onto the ten routes for ids past 10.
    readonly property int wsId: Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace
        ? Hyprland.focusedMonitor.activeWorkspace.id : 1
    readonly property int route: ((wsId - 1) % 10 + 10) % 10 + 1

    // The opponent's sprite is random: any foe-<n>.gif in assets (Showdown
    // gen5ani, same style as ally-back.gif), counted once at startup. Each
    // route keeps its own opponent for the session (seeded per boot), so
    // switching workspaces changes the encounter without the sprite
    // rerolling on every switch.
    property int foeSpriteCount: 0
    readonly property int foeSeed: Math.floor(Math.random() * 997)
    readonly property int foePick: foeSpriteCount > 0
        ? ((route * 31 + foeSeed) % foeSpriteCount) + 1 : 0

    Process {
        command: ["sh", "-c", "ls " + assetDir + "foe-*.gif 2>/dev/null | wc -l"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: wall.foeSpriteCount = parseInt(text.trim(), 10) || 0
        }
    }

    // ---------------------------------------------------------------- field

    Rectangle {
        anchors.fill: parent
        color: Skin.cell
    }

    Image {
        anchors.fill: parent
        source: wall.assetDir + "bg-" + wall.route + ".png"
        fillMode: Image.PreserveAspectCrop
        smooth: false
        visible: status === Image.Ready
        asynchronous: true
    }

    // ---------------------------------------------------------------- foe plate (top right)

    Rectangle {
        id: foePlate
        x: parent.width - 34 - 300
        y: 64
        width: 300
        height: foeCol.implicitHeight + 25
        color: Skin.strip
        border.width: 4
        border.color: Skin.inner
        visible: SysState.foe !== null && Skin.has("foe")

        // soft drop shadow (soft-shadows-only decision, 2026-08-20)
        SoftShadow {
            z: -1
            anchors.fill: parent
        }

        Column {
            id: foeCol
            x: 20
            y: 12
            width: parent.width - 40
            spacing: 9

            Item {
                width: parent.width
                height: foeName.implicitHeight

                Text {
                    id: foeName
                    text: SysState.foe ? SysState.foe.name : ""
                    color: Skin.text
                    font.family: Skin.fontLabel
                    font.pixelSize: 16
                }

                Text {
                    anchors.right: statusChip.left
                    anchors.rightMargin: 10
                    anchors.baseline: foeName.baseline
                    text: SysState.foe ? "LV " + SysState.foe.level : ""
                    color: Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.14
                }

                Rectangle {
                    id: statusChip
                    anchors.right: parent.right
                    width: chipText.implicitWidth + 12
                    height: chipText.implicitHeight + 4
                    color: Skin.accent

                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: "ENRAGED"
                        color: Skin.shadow
                        font.family: Skin.fontLabel
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.16
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 8

                Text {
                    id: foeHpLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "HP"
                    color: Skin.outer
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.16
                }

                HpBar {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - foeHpLabel.implicitWidth - 8
                    height: 9
                    fraction: SysState.foe ? SysState.foe.hp : 0
                    fillColor: Skin.hpColor(SysState.foe ? SysState.foe.hp : 0)
                }
            }
        }
    }

    // accent slash under the foe plate
    Rectangle {
        x: parent.width - 34 - 200
        y: 64 + 96
        width: 200
        height: 5
        color: Skin.accent
        visible: SysState.foe !== null && Skin.has("foe")
    }

    // ---------------------------------------------------------------- foe sprite (upper right)

    Column {
        visible: Skin.has("foe")
        x: parent.width - 96 - 238 + 44
        y: 170

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 150
            height: 150

            DashedSlot {
                anchors.fill: parent
                label: "FOE SPRITE"
                visible: !foeSprite.visible
            }

            AnimatedImage {
                id: foeSprite
                anchors.fill: parent
                // Empty until the count lands -- pointing at a file that may
                // not exist logged a warning every startup.
                source: wall.foePick > 0
                    ? wall.assetDir + "foe-" + wall.foePick + ".gif" : ""
                fillMode: Image.PreserveAspectFit
                smooth: false
                // Same battery rule as the ally's animation: it plays only
                // when someone can see it and the wire is paying for it.
                // Paused, it still shows a frame.
                playing: wall.bare && !SysState.onBattery
                         && status === AnimatedImage.Ready
                visible: status === AnimatedImage.Ready
                asynchronous: true
            }
        }

    }

    // ---------------------------------------------------------------- ally sprite (lower left)

    Column {
        visible: Skin.has("ally")
        x: 78
        // 240, up from the design's 178: the sprites read too small against
        // the full-panel field (user request 2026-08-21). Bottom edge stays
        // where the 178 slot put it.
        y: parent.height - 135 - 240

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 240
            height: 240

            DashedSlot {
                anchors.fill: parent
                label: "ALLY SPRITE"
                visible: !allyStill.visible && !allyAnim.visible
            }

            Image {
                id: allyStill
                anchors.fill: parent
                source: wall.assetDir + "ally-front.png"
                fillMode: Image.PreserveAspectFit
                smooth: false
                visible: status === Image.Ready && !allyAnim.visible
                asynchronous: true
            }

            AnimatedImage {
                id: allyAnim
                anchors.fill: parent
                source: wall.assetDir + "ally-back.gif"
                fillMode: Image.PreserveAspectFit
                smooth: false
                // Same rule as the foe: the gif is the sprite whenever it
                // loads -- covered or on battery it holds a paused frame
                // rather than swapping to the front sprite (user request
                // 2026-08-20). It only PLAYS when someone can see it and
                // the wire is paying for it.
                playing: wall.bare && !SysState.onBattery
                         && status === AnimatedImage.Ready
                visible: status === AnimatedImage.Ready
                asynchronous: true
            }
        }

    }

    // ---------------------------------------------------------------- ally plate (bottom right)

    Rectangle {
        id: allyPlate
        x: parent.width - 26 - 400
        y: parent.height - 34 - height
        width: 400
        height: allyCol.implicitHeight + 25
        color: Skin.strip
        border.width: 4
        border.color: Skin.inner

        SoftShadow {
            z: -1
            anchors.fill: parent
        }

        Column {
            id: allyCol
            x: 20
            y: 12
            width: parent.width - 40
            spacing: 9

            // badges left, name + LV right (the badges sit where the status
            // chip used to; the ally plate carries no status chip).
            Item {
                width: parent.width
                height: allyName.implicitHeight

                Row {
                    visible: Skin.has("types") && Skin.type1 !== ""
                    spacing: 8

                    Rectangle {
                        width: t1.implicitWidth + 14
                        height: t1.implicitHeight + 6
                        color: Skin.type1Hue

                        Text {
                            id: t1
                            anchors.centerIn: parent
                            text: Skin.type1
                            color: Skin.shadow
                            font.family: Skin.fontLabel
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.18
                        }
                    }

                    Rectangle {
                        visible: Skin.type2 !== "" && Skin.type2 !== "-"
                        width: t2.implicitWidth + 14
                        height: t2.implicitHeight + 6
                        color: Skin.type2Hue

                        Text {
                            id: t2
                            anchors.centerIn: parent
                            text: Skin.type2
                            color: Skin.shadow
                            font.family: Skin.fontLabel
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.18
                        }
                    }
                }

                Text {
                    id: allyLv
                    visible: Skin.has("lv")
                    anchors.right: parent.right
                    anchors.baseline: allyName.baseline
                    text: "LV " + SysState.level
                    color: Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.14
                }

                Text {
                    id: allyName
                    anchors.right: allyLv.left
                    anchors.rightMargin: 10
                    text: Skin.species
                    color: Skin.text
                    font.family: Skin.fontLabel
                    font.pixelSize: 16
                }
            }

            Row {
                width: parent.width
                spacing: 8

                Text {
                    id: allyHpLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "HP"
                    color: Skin.outer
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.16
                }

                HpBar {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - allyHpLabel.implicitWidth - allyHpNum.implicitWidth - 16
                    height: 9
                    fraction: SysState.hp
                    fillColor: Skin.hpColor(SysState.hp)
                    alarm: SysState.hp <= 0.2
                }

                Text {
                    id: allyHpNum
                    anchors.verticalCenter: parent.verticalCenter
                    text: SysState.hpNum
                    color: Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.12
                }
            }

            // EXP sliver: uptime, NET hue; wraps at 24 hours awake (same
            // rule as the lock screen).
            Row {
                visible: Skin.has("exp")
                width: parent.width
                spacing: 8

                Text {
                    id: expLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "EXP"
                    color: Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.16
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - expLabel.implicitWidth - 8
                    height: 5
                    color: Skin.inner

                    Rectangle {
                        width: Math.round(parent.width * SysState.expFrac)
                        height: parent.height
                        color: Skin.net
                    }
                }
            }
        }
    }

    // accent slash above the ally plate: anchored to the plate's actual top
    // rather than a fixed offset, which floated it too high above the
    // nameplate (user request 2026-08-21). 6px gap, same as the foe slash.
    Rectangle {
        x: parent.width - 42 - 230
        y: allyPlate.y - 11
        width: 230
        height: 5
        color: Skin.accent
    }

    // ---------------------------------------------------------------- clock (top left)

    Column {
        x: 34
        y: 64
        spacing: 26

        Column {
            spacing: 4

            WidgetText {
                text: SysState.time
                size: 56
                shadowOffset: 4
            }

            WidgetText {
                text: SysState.date
                size: 10
                tracking: 10 * 0.2
            }

            // Which workspace this is -- each one is its own route.
            WidgetText {
                text: "ROUTE " + wall.route
                size: 12
                tracking: 12 * 0.2
            }
        }

    }
}
