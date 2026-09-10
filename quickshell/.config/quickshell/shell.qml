// Quickshell entry point.
//
// One process hosts every surface -- wallpaper, bar, launcher, OSD, power
// and details menus, lock, toasts, calendar -- so they share one skin and one
// set of components. Each is built once at startup and toggled with `visible`
// rather than constructed on demand: the surface appears in a single frame
// instead of after a QML load, and nothing in it polls or animates while it
// is hidden.
//
// The IPC targets below are what the Hyprland keybinds call, e.g.
//
//     qs ipc call launcher toggle

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    property bool launcherOpen: false

    // Quickshell exits when its last window closes, which for a config whose
    // only surface is an on-demand launcher means it exits a moment after
    // startup and again every time the launcher is dismissed. Connecting to
    // lastWindowClosed overrides that default and leaves the process resident,
    // which is the whole point of building the launcher once and toggling it.
    Connections {
        target: Quickshell

        function onLastWindowClosed(): void {
            // Deliberately empty. Handling the signal is what keeps us alive.
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            launcher.openAs("apps");
            root.launcherOpen = !root.launcherOpen;
        }

        function open(): void {
            launcher.openAs("apps");
            root.launcherOpen = true;
        }

        function close(): void {
            root.launcherOpen = false;
        }

        // The list modes from turn 25d/25e ride the same surface: the
        // clipboard history (SUPER + V) and the glyph picker (SUPER + G).
        function clipboard(): void {
            launcher.openAs("clip");
            root.launcherOpen = true;
        }

        function glyphs(): void {
            launcher.openAs("glyphs");
            root.launcherOpen = true;
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            sessionLock.wantLocked = true;
        }

        // After resume Hyprland delivers only key releases to the lock
        // surface that existed before suspend (MACHINE.md, "The lock screen
        // goes deaf after suspend"). A brand-new ext-session-lock object gets
        // a new surface and a fresh keyboard enter, which is what fixlock
        // achieves with a new hyprlock process. Flipping wantLocked off and
        // on in one call sends unlock_and_destroy and lock in the same flush,
        // so Hyprland never renders an unlocked frame between them. No-op
        // when not locked, so hypridle's after_sleep_cmd can call it
        // unconditionally.
        function relock(): void {
            if (!sessionLock.wantLocked) return;
            sessionLock.wantLocked = false;
            sessionLock.wantLocked = true;
        }
    }

    // The lock screen from turn 13a. Replaces hyprlock; see Lock.qml for the
    // security shape. Lock with `qs ipc call lock lock` -- there is
    // deliberately no unlock IPC, only PAM.
    Lock {
        id: sessionLock
    }

    // The hardware keys. Volume keys move 5 points on the 5% grid;
    // brightness keys move one bar of the 8-step meter (its readout is bars
    // only, so a press always visibly adds or removes one).
    IpcHandler {
        target: "keys"

        function volup(): void { SysState.nudgeVol(5); }
        function voldown(): void { SysState.nudgeVol(-5); }
        function brightup(): void { SysState.setBright8(SysState.bright8 + 1); }
        function brightdown(): void { SysState.setBright8(SysState.bright8 - 1); }
    }

    property bool detailsOpen: false

    IpcHandler {
        target: "details"

        function toggle(): void {
            root.detailsOpen = !root.detailsOpen;
        }

        function close(): void {
            root.detailsOpen = false;
        }
    }

    property bool notifHistoryOpen: false

    IpcHandler {
        target: "notifs"

        function history(): void {
            root.notifHistoryOpen = !root.notifHistoryOpen;
        }

        function dnd(): void {
            Notifs.toggleDnd();
        }

        function dismiss(): void {
            Notifs.dismissAll();
        }
    }

    property bool powerOpen: false

    IpcHandler {
        target: "power"

        function toggle(): void {
            root.powerOpen = !root.powerOpen;
        }

        function close(): void {
            root.powerOpen = false;
        }

        // The details menu's SESSION rows land here: open straight onto
        // the red confirm line for one named action (RESTART is not on the
        // menu's grid at all, so opening the plain menu would dead-end).
        function confirm(name: string): void {
            root.powerOpen = true;
            powerMenu.openConfirm(name);
        }
    }

    Launcher {
        id: launcher
        visible: root.launcherOpen
        onDismissed: root.launcherOpen = false
    }

    // The wallpaper. Owns the background layer; hyprpaper is retired.
    Wallpaper {}

    // The desk todo list, on the bottom layer: only there on an empty
    // workspace, clickable there. See Todo.qml.
    Todo {}

    // The 32px status bar. Always on, event-driven. Its clock is the
    // pointer's way into the calendar page (SUPER + N is the keyboard's).
    Bar {
        onClockActivated: root.notifHistoryOpen = true
    }

    // The OSD from turn 15e. Shows itself on volume/brightness changes.
    Osd {}

    // The power menu from turn 19a (SUPER + ESC).
    PowerMenu {
        id: powerMenu
        visible: root.powerOpen
        onDismissed: root.powerOpen = false
    }

    // The details menu (SUPER + D): the one-screen control deck.
    DetailsMenu {
        visible: root.detailsOpen
        onDismissed: root.detailsOpen = false
    }

    // Notification toasts from turn 25a. Always alive; shows itself while
    // Notifs presents something. The daemon itself is the Notifs singleton.
    Toasts {}

    // The calendar + log page (SUPER + N, or the bar clock).
    NotifHistory {
        visible: root.notifHistoryOpen
        onDismissed: root.notifHistoryOpen = false
    }
}
