// The lock screen's creature centrepiece, from turn 13a of the
// creature-shell handoff: the creature is recalled into its capture device,
// and waking releases it. The recoloured capture device, the creature card,
// the four moves that resume on wake, and the blinking prompt arrow. This is
// the costume half of Lock.qml -- loaded only when the skin's `lock` variant
// says "card", so the plain lock never constructs any of it. The clock, the
// prompt text and the password field live in Lock.qml in both variants.

import QtQuick
import Quickshell

Item {
    id: card

    // Fed by Lock.qml: the frame geometry the card and the move slots hang
    // from.
    required property int frameX
    required property int frameW

    // ---------------- capture device
    // ball.png is rendered by skinctl at 270px (18 cells x 15).
    // 180 logical is exactly 270 physical at this panel's 1.5 scale,
    // so every sprite cell lands on whole pixels.
    Image {
        id: ballImg
        x: 138
        y: 248
        width: 180
        height: 180
        source: (Quickshell.env("XDG_STATE_HOME")
                 || (Quickshell.env("HOME") + "/.local/state")) + "/skins/ball.png"
        fillMode: Image.PreserveAspectFit
        smooth: false
        asynchronous: true

        // The button blinks at the creature's blink speed, as the
        // design's capture device always did. The sprite's button is
        // the 3x3 cell block at columns 5-7, rows 11-13 of the
        // 18-cell map; at 180px each cell is 10px. The overlay is
        // accent, alternating with the sprite's own white beneath.
        Blink {
            x: 50
            y: 110
            width: 30
            height: 30

            Rectangle {
                width: 30
                height: 30
                color: Skin.accent
            }
        }
    }

    Rectangle {
        x: 158
        y: 452
        width: 140
        height: 28
        color: Skin.strip
        border.width: 3
        border.color: Skin.inner

        Text {
            anchors.centerIn: parent
            text: Skin.ballWord
            color: Skin.body
            font.family: Skin.fontLabel
            font.pixelSize: 10
            font.letterSpacing: 10 * 0.2
        }
    }

    // ---------------- creature card
    Rectangle {
        x: 408
        y: 212
        width: card.frameW + card.frameX - 34 - 408
        height: cardCol.implicitHeight + 48
        color: Skin.strip
        border.width: 4
        border.color: Skin.inner

        Column {
            id: cardCol
            x: 26
            y: 24
            width: parent.width - 52
            spacing: 14

            Item {
                width: parent.width
                height: cardName.implicitHeight

                Text {
                    id: cardName
                    text: Skin.species
                    color: Skin.text
                    font.family: Skin.fontLabel
                    font.pixelSize: 26
                }

                Text {
                    x: cardName.implicitWidth + 14
                    visible: Skin.has("lv")
                    anchors.baseline: cardName.baseline
                    text: "LV " + SysState.level
                    color: Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 12
                    font.letterSpacing: 12 * 0.14
                }
            }

            Row {
                visible: Skin.has("types") && Skin.type1 !== ""
                spacing: 7

                Rectangle {
                    width: cardT1.implicitWidth + 16
                    height: cardT1.implicitHeight + 6
                    color: Skin.type1Hue

                    Text {
                        id: cardT1
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
                    width: cardT2.implicitWidth + 16
                    height: cardT2.implicitHeight + 6
                    color: Skin.type2Hue

                    Text {
                        id: cardT2
                        anchors.centerIn: parent
                        text: Skin.type2
                        color: Skin.shadow
                        font.family: Skin.fontLabel
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.18
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 10

                Text {
                    id: cardHpLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "HP"
                    color: Skin.outer
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.16
                }

                HpBar {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - cardHpLabel.implicitWidth
                           - cardHpNum.implicitWidth - 20
                    height: 12
                    fraction: SysState.hp
                    fillColor: Skin.hpColor(SysState.hp)
                    alarm: SysState.hp <= 0.2
                }

                Text {
                    id: cardHpNum
                    anchors.verticalCenter: parent.verticalCenter
                    text: SysState.hpNum
                    color: Skin.body
                    font.family: Skin.fontLabel
                    font.pixelSize: 12
                    font.letterSpacing: 12 * 0.12
                }
            }

            Row {
                visible: Skin.has("exp")
                width: parent.width
                spacing: 10

                Text {
                    id: cardExpLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "EXP"
                    color: Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.16
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - cardExpLabel.implicitWidth
                           - cardExpNum.implicitWidth - 20
                    height: 6
                    color: Skin.inner

                    Rectangle {
                        width: Math.round(parent.width * SysState.expFrac)
                        height: parent.height
                        color: Skin.net
                    }
                }

                Text {
                    id: cardExpNum
                    anchors.verticalCenter: parent.verticalCenter
                    // EXP is uptime, wrapping at 24 hours awake
                    // (same rule as the wallpaper).
                    text: "EXP TO NEXT LV — "
                          + (100 - Math.round(SysState.expFrac * 100)) + "%"
                    color: Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.12
                }
            }

            Text {
                width: parent.width
                text: Skin.crNote
                color: Skin.body
                font.family: Skin.fontBody
                font.pixelSize: 16
                wrapMode: Text.WordWrap
            }
        }
    }

    // ---------------- moves that resume on wake
    Text {
        x: 78
        y: 508
        text: "MOVES — RESUME ON WAKE"
        color: Skin.dim
        font.family: Skin.fontLabel
        font.pixelSize: 10
        font.letterSpacing: 10 * 0.2
    }

    // The moves are whatever is actually running when the machine is
    // recalled -- window classes from the compositor, most windows
    // first, top four. Slots past the running count show the empty
    // word.
    Row {
        x: 78
        y: 532
        spacing: 10

        Repeater {
            model: {
                const r = Apps.runningApps().slice(0, 4);
                while (r.length < 4) r.push(null);
                return r;
            }

            Rectangle {
                required property var modelData

                width: (card.frameW - 68 - 30) / 4
                height: 66
                color: Skin.cell
                border.width: 3
                border.color: Skin.inner

                Column {
                    visible: parent.modelData !== null
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 24
                    spacing: 8

                    Item {
                        width: parent.width
                        height: slotTag.implicitHeight

                        Text {
                            id: slotTag
                            text: parent.parent.parent.modelData
                                ? parent.parent.parent.modelData.tag : ""
                            color: Skin.categoryColor(slotTag.text)
                            font.family: Skin.fontLabel
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.18
                        }

                        Text {
                            anchors.right: parent.right
                            text: parent.parent.parent.modelData
                                ? Apps.ppFor(parent.parent.parent.modelData.match) : ""
                            color: Skin.dim
                            font.family: Skin.fontLabel
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.10
                        }
                    }

                    Text {
                        width: parent.width
                        text: parent.parent.modelData ? parent.parent.modelData.name : ""
                        color: Skin.text
                        font.family: Skin.fontLabel
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                Text {
                    visible: parent.modelData === null
                    anchors.centerIn: parent
                    text: Skin.emptyWord
                    color: Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.14
                }
            }
        }
    }

    // ---------------- prompt arrow
    Blink {
        x: 78
        y: 630
        width: promptArrow.implicitWidth
        height: promptArrow.implicitHeight

        Text {
            id: promptArrow
            text: Skin.glyph
            color: Skin.accent
            font.family: Skin.fontLabel
            font.pixelSize: 14
        }
    }
}
