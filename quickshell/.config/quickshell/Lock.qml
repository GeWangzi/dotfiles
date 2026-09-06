// The lock screen: the desk's wallpaper, blurred under a scrim, with the
// clock and date and a centred password field on top and nothing else.
//
// This replaced hyprlock (2026-08-19). hyprlock's widget set fought the
// design -- no blink, pango-over-cmd hacks for every live figure, and an
// async text pipeline that silently stalled on this config. Here the lock is
// a normal QML surface: same Skin tokens, same Blink component, and SysState
// keeps updating while locked because it is the same process.
//
// Security shape: WlSessionLock speaks ext-session-lock-v1 -- the compositor
// holds the lock, so if this process dies the session STAYS locked (Hyprland
// drops to its red lockdead screen; run hyprlock from a TTY to recover).
// Authentication is PAM via Quickshell.Services.Pam. hyprlock stays
// installed as the fallback locker.
//
// Typing anywhere types the password: the field is the prompt.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam

WlSessionLock {
    id: lock

    property bool wantLocked: false
    locked: wantLocked

    surface: WlSessionLockSurface {
        id: surf

        color: Skin.bg

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

            // ---------------- background
            // The desk's wallpaper (the same file Wallpaper.qml hangs),
            // blurred, under a `bg` scrim (0.45; 0.35 left the dim hint faint
            // over the bright parts of the picture) so the type reads on any
            // picture. The whole stack sits in one cached layer: MultiEffect
            // re-runs its shader on every scene-graph frame, and the caret
            // blinks every second, so without the layer the blur would be
            // recomputed once a second for nothing. With it the blur renders
            // once and the blinks only composite a texture.
            //
            // If the file is absent (fresh clone, no `skinctl wallpaper` yet)
            // this stays hidden and the surface's flat `bg` shows, the same
            // fallback the desk has.
            Item {
                visible: wallArt.status === Image.Ready
                anchors.fill: parent
                layer.enabled: visible

                Image {
                    id: wallArt
                    visible: false
                    anchors.fill: parent
                    source: Quickshell.env("HOME") + "/.config/quickshell/assets/wallpaper.jpg"
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    asynchronous: true
                }

                MultiEffect {
                    anchors.fill: parent
                    source: wallArt
                    blurEnabled: true
                    blur: 0.6
                    blurMax: 48
                    autoPaddingEnabled: false
                }

                Rectangle {
                    anchors.fill: parent
                    color: Skin.bg
                    opacity: 0.45
                }
            }

            // ---------------- clock: the big centred figure the design leads with
            Text {
                x: Math.round((surf.width - implicitWidth) / 2)
                y: Math.round(surf.height * 0.24)
                text: SysState.time
                color: Skin.text
                font.family: Skin.fontLabel
                font.bold: true
                font.pixelSize: 120
            }

            Text {
                x: Math.round((surf.width - implicitWidth) / 2)
                y: Math.round(surf.height * 0.24) + 158
                text: Qt.formatDateTime(SysState.clock.date, "dddd dd MMMM yyyy").toUpperCase()
                color: Skin.dim
                font.family: Skin.fontLabel
                font.pixelSize: 12
                font.letterSpacing: 12 * Skin.trackWide
            }

            // The field is the prompt: it fills as you type, anywhere. Square
            // blocks centred over a bare rule.
            Column {
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

                        Caret {
                            visible: !surf.checking
                            anchors.verticalCenter: parent.verticalCenter
                            lineHeight: 17
                        }
                    }

                    Caret {
                        visible: surf.password === "" && !surf.checking
                        anchors.centerIn: parent
                        lineHeight: 17
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
                        : "ENTER PASSPHRASE"
                    color: surf.fails > 0 && surf.password === ""
                        ? Skin.critical : Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * Skin.trackLabel
                }
            }
        }
    }
}
