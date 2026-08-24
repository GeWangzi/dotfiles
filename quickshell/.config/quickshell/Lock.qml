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
                    text: Skin.lex("lock_tab", "LOCKED")
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

            // ---------------- the creature centrepiece (costume only)
            Loader {
                anchors.fill: parent
                active: Skin.variant("lock", "plain") === "card"
                sourceComponent: LockCard {
                    frameX: surf.frameX
                    frameW: surf.frameW
                }
            }

            // ---------------- battery (plain only -- the card carries HP)
            Row {
                visible: surf.plainLock
                x: 75
                y: 186
                spacing: 10

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
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.10
                }
            }

            Text {
                id: promptText
                x: surf.plainLock ? Math.round((surf.width - implicitWidth) / 2) : 104
                y: surf.plainLock ? Math.round(surf.height * 0.60) - 34 : 632
                text: surf.checking ? "CHECKING..."
                                    : Skin.lex("lock_prompt", "TYPE YOUR PASSWORD THEN ENTER")
                color: Skin.text
                font.family: Skin.fontLabel
                font.pixelSize: 12
                font.letterSpacing: 12 * 0.16
            }

            // The field is the prompt: it fills as you type, anywhere. The
            // card variant parks it bottom right; the plain lock centres it.
            Rectangle {
                x: surf.plainLock ? Math.round((surf.width - width) / 2)
                                  : surf.frameX + surf.frameW - 34 - width
                y: surf.plainLock ? Math.round(surf.height * 0.60) : 620
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
