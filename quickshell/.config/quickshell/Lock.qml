// The lock screen. Plain by default: the frame on the void, the clock and
// date, a battery line, and a centred password field. The creature costume
// (skin variant lock = "card") loads LockCard.qml on top -- the recoloured
// capture device, the creature card, and the four moves that resume on wake,
// from turn 13a of the creature-shell handoff.
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
        // Live PP figures for the move slots while the card is up. The plain
        // lock has no move slots, so it does not pay for the polling.
        Apps.polling = locked && Skin.variant("lock", "plain") === "card";
    }

    surface: WlSessionLockSurface {
        id: surf

        readonly property bool plainLock: Skin.variant("lock", "plain") !== "card"

        color: Skin.bg

        // The plain (Console) lock inset-frames the whole screen at 22px;
        // the card costume keeps the 44px window its layout was drawn on.
        readonly property int frameX: plainLock ? 22 : 44
        readonly property int frameY: plainLock ? 22 : 44
        readonly property int frameW: width - 2 * frameX
        readonly property int frameH: height - 2 * frameY

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

            // ---------------- frame
            // Plain (Console dress): a 2px inset rule on the void, broken
            // top-centre by the lock glyph -- the icon IS the "locked" label.
            // Card costume: the shadowed window the card layout was drawn on.
            SoftShadow {
                visible: !surf.plainLock
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
                color: surf.plainLock ? "transparent" : Skin.window
                border.width: surf.plainLock ? 2 : 5
                border.color: surf.plainLock ? Skin.inner : Skin.outer
            }

            Rectangle {
                visible: surf.plainLock
                anchors.horizontalCenter: parent.horizontalCenter
                y: surf.frameY - height / 2
                width: 52
                height: 30
                color: Skin.bg

                Icon {
                    anchors.centerIn: parent
                    name: "lock"
                    size: 18
                    color: Skin.dim
                }
            }

            // Card costume keeps its text tab.
            Rectangle {
                visible: !surf.plainLock
                x: surf.frameX + 22
                y: surf.frameY - height
                width: tabText.implicitWidth + 22
                height: tabText.implicitHeight + 8
                color: Skin.outer

                Text {
                    id: tabText
                    anchors.centerIn: parent
                    text: Skin.lex("lock_tab", "LOCKED")
                    color: Skin.window
                    font.family: Skin.fontLabel
                    font.pixelSize: 12
                    font.letterSpacing: 12 * 0.18
                }
            }

            // ---------------- clock
            // Plain: the big centred figure the Console design leads with.
            // Card: top-left, where the card layout expects it.
            Text {
                x: surf.plainLock ? Math.round((surf.width - implicitWidth) / 2) : 72
                y: surf.plainLock ? Math.round(surf.height * 0.24) : 70
                text: SysState.time
                color: Skin.text
                font.family: Skin.fontLabel
                font.bold: surf.plainLock
                font.pixelSize: surf.plainLock ? 120 : 54
            }

            Text {
                x: surf.plainLock ? Math.round((surf.width - implicitWidth) / 2) : 75
                y: surf.plainLock ? Math.round(surf.height * 0.24) + 158 : 146
                text: Qt.formatDateTime(SysState.clock.date, "dddd dd MMMM yyyy").toUpperCase()
                color: Skin.dim
                font.family: Skin.fontLabel
                font.pixelSize: 12
                font.letterSpacing: 12 * 0.22
            }

            // ---------------- the creature centrepiece (costume only)
            Loader {
                anchors.fill: parent
                active: Skin.variant("lock", "plain") === "card"
                sourceComponent: LockCard {
                    frameX: surf.frameX
                    frameW: surf.frameW
                }
            }

            // ---------------- footer (plain only -- the card carries HP)
            // A ruled strip along the frame's bottom edge: who is locked out
            // on the left, the battery's own words on the right.
            Item {
                visible: surf.plainLock
                x: surf.frameX + 2
                y: surf.frameY + surf.frameH - 42
                width: surf.frameW - 4
                height: 40

                Rectangle {
                    width: parent.width
                    height: 2
                    color: Skin.inner
                }

                Row {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "user"
                        size: 13
                        color: Skin.dim
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (Quickshell.env("USER") || "").toUpperCase()
                        color: Skin.dim
                        font.family: Skin.fontLabel
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.14
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    BatteryIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        fraction: SysState.hp
                        color: Skin.dim
                        fillColor: Skin.hpColor(SysState.hp)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: SysState.hpNum
                        color: Skin.dim
                        font.family: Skin.fontLabel
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.10
                    }
                }
            }

            // Card costume keeps the worded prompt; the plain lock's hint
            // lives under the field.
            Text {
                id: promptText
                visible: !surf.plainLock
                x: 104
                y: 632
                text: surf.checking ? "CHECKING..."
                                    : Skin.lex("lock_prompt", "TYPE YOUR PASSWORD THEN ENTER")
                color: Skin.text
                font.family: Skin.fontLabel
                font.pixelSize: 12
                font.letterSpacing: 12 * 0.16
            }

            // The field is the prompt: it fills as you type, anywhere. The
            // card variant parks its boxed field bottom right; the plain lock
            // centres square blocks over a bare rule (Console dress).
            Column {
                visible: surf.plainLock
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(surf.height * 0.60)
                spacing: 12

                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 280
                    height: 20

                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        visible: surf.password !== ""

                        Repeater {
                            model: Math.min(20, surf.password.length)

                            Rectangle {
                                width: 10
                                height: 10
                                anchors.verticalCenter: parent.verticalCenter
                                color: surf.checking ? Skin.dim : Skin.body
                            }
                        }

                        Rectangle {
                            visible: !surf.checking
                            width: 9
                            height: 17
                            anchors.verticalCenter: parent.verticalCenter
                            color: Skin.accent
                        }
                    }

                    Rectangle {
                        visible: surf.password === "" && !surf.checking
                        anchors.centerIn: parent
                        width: 9
                        height: 17
                        color: Skin.accent
                    }
                }

                Rectangle {
                    width: 280
                    height: 2
                    color: surf.fails > 0 && surf.password === ""
                        ? Skin.critical : Skin.inner
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: surf.checking ? "CHECKING..."
                        : surf.fails > 0 && surf.password === ""
                        ? "AUTHENTICATION FAILED — TRY AGAIN"
                        : Skin.lex("lock_type", "ENTER PASSPHRASE")
                    color: surf.fails > 0 && surf.password === ""
                        ? Skin.critical : Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.14
                }
            }

            // Card costume's boxed field, unchanged.
            Rectangle {
                visible: !surf.plainLock
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
                        : Skin.lex("lock_type", "TYPE TO UNLOCK")
                    color: surf.fails > 0 ? Skin.critical : Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.14
                }
            }
        }
    }
}
