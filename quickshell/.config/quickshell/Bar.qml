// The status bar, from turn 13b of the creature-shell handoff: a 34px HP/PP
// header, not a tray.
//
//   creature name, HP bar + figure, status chips (only when the condition
//   is real), then wifi, volume and the time. LV lives on the wallpaper
//   plate and the menus, not here (user request 2026-08-20).
//
//   The design's in-combat foe segment (`VS <FOE>`) was built and removed at
//   the user's request (2026-08-19) -- the bar holds one state. The foe
//   object still drives the wallpaper's foe plate.
//
// HP is the battery -- there is no battery indicator anywhere else, and no
// app/PP segment on the bar. Chips sit inline so the height never changes.
// There are no workspaces on the bar either: workspaces are SUPER+number.
//
// Every Silkscreen size is the design's rounded up to even (9 -> 10,
// 11 -> 12), because the panel runs at scale 1.5. See fonts/README.md.

import QtQuick
import Quickshell

PanelWindow {
    id: bar

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: 34
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: Skin.strip

        // border-bottom: 5px solid outer
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 5
            color: Skin.outer
        }

        // Content row, vertically centred in the 29px above the rule.
        Row {
            id: content
            x: 12
            height: parent.height - 5
            spacing: 14

            // ---- the machine itself
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Skin.species
                color: Skin.text
                font.family: "Silkscreen"
                font.pixelSize: 12
            }

            HpBar {
                anchors.verticalCenter: parent.verticalCenter
                width: 150
                height: 9
                fraction: SysState.hp
                fillColor: Skin.hpColor(SysState.hp)
                alarm: SysState.hp <= 0.2
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: SysState.hpNum
                color: Skin.body
                font.family: "Silkscreen"
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.10
            }

            // Status conditions: filled chips, only when real (turn 19c).
            Repeater {
                model: SysState.chips

                Chip {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    label: modelData.label
                    hue: modelData.hue
                }
            }

            // SUB is a field effect the machine raised itself, so it is a
            // dashed outline, never a filled chip (turn 20).
            Chip {
                visible: SysState.sub
                anchors.verticalCenter: parent.verticalCenter
                label: "SUB"
                hue: Skin.accent
                fieldEffect: true
            }
        }

        // ---- right side: wifi, volume, clock
        Row {
            id: rightSide
            anchors.right: parent.right
            anchors.rightMargin: 12
            height: parent.height - 5
            spacing: 14

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: SysState.wifiUp ? "WIFI" : "NO LINK"
                    color: Skin.dim
                    font.family: "Silkscreen"
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.14
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Repeater {
                        model: 4

                        Rectangle {
                            required property int index
                            width: 5
                            height: 11
                            color: index < SysState.wifiBars ? Skin.net : Skin.inner
                        }
                    }
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "VOL"
                    color: Skin.dim
                    font.family: "Silkscreen"
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.14
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Repeater {
                        model: 4

                        Rectangle {
                            required property int index
                            width: 5
                            height: 11
                            color: index < Math.ceil(SysState.volPct / 25)
                                ? Skin.text : Skin.inner
                        }
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: SysState.time
                color: Skin.text
                font.family: "Silkscreen"
                font.pixelSize: 12
            }
        }
    }
}
