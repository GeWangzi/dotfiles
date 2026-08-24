// The battle field's furniture, from turn 16a of the creature-shell handoff:
// foe plate top right, ally plate bottom right, two sprite slots. This is
// the wallpaper half of the creature costume -- Wallpaper.qml loads it only
// when the skin's `field` variant says "creature", so the plain shell never
// constructs any of it. The clock and the background image stay in
// Wallpaper.qml; everything here sits on top of them.
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
import Quickshell.Io

Item {
    id: field

    // Fed by Wallpaper.qml: the asset folder, whether the focused workspace
    // is bare, and which route (workspace) is showing.
    required property string assetDir
    required property bool bare
    required property int route

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
        command: ["sh", "-c", "ls " + field.assetDir + "foe-*.gif 2>/dev/null | wc -l"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: field.foeSpriteCount = parseInt(text.trim(), 10) || 0
        }
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
                source: field.foePick > 0
                    ? field.assetDir + "foe-" + field.foePick + ".gif" : ""
                fillMode: Image.PreserveAspectFit
                smooth: false
                // Same battery rule as the ally's animation: it plays only
                // when someone can see it and the wire is paying for it.
                // Paused, it still shows a frame.
                playing: field.bare && !SysState.onBattery
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
                source: field.assetDir + "ally-front.png"
                fillMode: Image.PreserveAspectFit
                smooth: false
                visible: status === Image.Ready && !allyAnim.visible
                asynchronous: true
            }

            AnimatedImage {
                id: allyAnim
                anchors.fill: parent
                source: field.assetDir + "ally-back.gif"
                fillMode: Image.PreserveAspectFit
                smooth: false
                // Same rule as the foe: the gif is the sprite whenever it
                // loads -- covered or on battery it holds a paused frame
                // rather than swapping to the front sprite (user request
                // 2026-08-20). It only PLAYS when someone can see it and
                // the wire is paying for it.
                playing: field.bare && !SysState.onBattery
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
        visible: Skin.has("ally")

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
        visible: Skin.has("ally")
    }
}
