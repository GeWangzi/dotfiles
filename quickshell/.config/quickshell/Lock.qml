// The lock screen, from turn 13a of the creature-shell handoff: the creature
// is recalled into its capture device, and waking releases it. The frame on
// the void, the recoloured capture device and creature card in the middle,
// the four moves that resume on wake, and a blinking PRESS ANY KEY TO
// CONTINUE. No in-battle status chip, no battery indicator -- HP is the
// battery, on the card like everything else.
//
// This replaced hyprlock (2026-08-19). hyprlock's widget set fought the
// design -- no blink, pango-over-cmd hacks for every live figure, and an
// async text pipeline that silently stalled on this config. Here the lock is
// a normal QML surface: same Skin tokens, same HpBar/Blink components, and
// SysState keeps updating while locked because it is the same process.
//
// Security shape: WlSessionLock speaks ext-session-lock-v1 -- the compositor
// holds the lock, so if this process dies the session STAYS locked (Hyprland
// drops to its red lockdead screen; run hyprlock from a TTY to recover).
// Authentication is PAM via Quickshell.Services.Pam. hyprlock stays
// installed as the fallback locker.
//
// Typing anywhere types the password: the field is the prompt.

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam

WlSessionLock {
    id: lock

    property bool wantLocked: false
    locked: wantLocked

    onLockedChanged: {
        // Live PP figures for the move slots while the card is up.
        Apps.polling = locked;
    }

    surface: WlSessionLockSurface {
        id: surf

        color: Skin.bg

        readonly property int frameX: 44
        readonly property int frameY: 44
        readonly property int frameW: width - 88
        readonly property int frameH: height - 88

        property string password: ""
        property bool checking: false
        property int fails: 0

        PamContext {
            id: pam

            // The same PAM stack hyprlock uses (auth include login). Wrong
            // attempts count toward faillock like any other login.
            config: "hyprlock"

            onPamMessage: {
                if (responseRequired) respond(surf.password);
            }

            onCompleted: result => {
                surf.checking = false;
                surf.password = "";
                if (result === PamResult.Success) {
                    lock.wantLocked = false;
                } else {
                    surf.fails++;
                }
            }
        }

        function submit() {
            if (checking || password === "") return;
            checking = true;
            pam.start();
        }

        Item {
            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                if (surf.checking) return;
                switch (event.key) {
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    surf.submit();
                    break;
                case Qt.Key_Backspace:
                    surf.password = surf.password.slice(0, -1);
                    break;
                case Qt.Key_Escape:
                    surf.password = "";
                    break;
                default:
                    if (event.text && event.text.length === 1 && event.text >= " ")
                        surf.password += event.text;
                    else
                        return;
                }
                event.accepted = true;
            }

            // ---------------- frame: soft shadow, window, tab
            // (soft-shadows-only decision, 2026-08-20)
            SoftShadow {
                x: surf.frameX
                y: surf.frameY
                width: surf.frameW
                height: surf.frameH
            }

            Rectangle {
                x: surf.frameX
                y: surf.frameY
                width: surf.frameW
                height: surf.frameH
                color: Skin.window
                border.width: 5
                border.color: Skin.outer
            }

            // Tab lost its hard shadow ring with the soft-shadows decision,
            // and sits flush on the frame edge -- nothing pokes below it.
            Rectangle {
                x: surf.frameX + 22
                y: surf.frameY - height
                width: tabText.implicitWidth + 22
                height: tabText.implicitHeight + 8
                color: Skin.outer

                Text {
                    id: tabText
                    anchors.centerIn: parent
                    text: "RELEASE"
                    color: Skin.window
                    font.family: Skin.fontLabel
                    font.pixelSize: 12
                    font.letterSpacing: 12 * 0.18
                }
            }

            // ---------------- clock
            Text {
                x: 72
                y: 70
                text: SysState.time
                color: Skin.text
                font.family: Skin.fontLabel
                font.pixelSize: 54
            }

            Text {
                x: 75
                y: 146
                text: Qt.formatDateTime(SysState.clock.date, "dddd dd MMMM yyyy").toUpperCase()
                color: Skin.dim
                font.family: Skin.fontLabel
                font.pixelSize: 12
                font.letterSpacing: 12 * 0.22
            }

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
                width: surf.frameW + surf.frameX - 34 - 408
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

                        width: (surf.frameW - 68 - 30) / 4
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

            // ---------------- prompt + password
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

            Text {
                x: 104
                y: 632
                text: surf.checking ? "CHECKING..." : "PRESS ANY KEY TO CONTINUE"
                color: Skin.text
                font.family: Skin.fontLabel
                font.pixelSize: 12
                font.letterSpacing: 12 * 0.16
            }

            // The field is the prompt: it fills as you type, anywhere.
            Rectangle {
                x: surf.frameX + surf.frameW - 34 - width
                y: 620
                width: 340
                height: 44
                color: Skin.cell
                border.width: 4
                border.color: surf.fails > 0 && surf.password === ""
                    ? Skin.critical : Skin.inner

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: surf.password !== ""

                    Repeater {
                        model: Math.min(24, surf.password.length)

                        Rectangle {
                            width: 8
                            height: 14
                            color: surf.checking ? Skin.dim : Skin.accent
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: surf.password === ""
                    text: surf.fails > 0
                        ? "AUTHENTICATION FAILED — TRY AGAIN"
                        : "TYPE TO RELEASE"
                    color: surf.fails > 0 ? Skin.critical : Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.14
                }
            }
        }
    }
}
