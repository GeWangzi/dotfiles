// Quickshell entry point.
//
// Right now this hosts one surface, the launcher. The toast, status bar and
// control center from the same design handoff are meant to join it here, which
// is the point of using a shell runtime rather than four separate programs:
// one process, one skin, one set of shared components.
//
// The launcher is built once at startup and toggled with `visible` rather than
// being constructed on demand. That costs a few MB of resident memory and buys
// two things: the surface appears in a single frame instead of after a QML
// load, and nothing in it polls or animates while it is hidden.
//
// Toggle it from outside with:
//
//     qs ipc call launcher toggle
//
// which is what the Hyprland keybind runs.

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
    }

    // The lock screen from turn 13a. Replaces hyprlock; see Lock.qml for the
    // security shape. Lock with `qs ipc call lock lock` -- there is
    // deliberately no unlock IPC, only PAM.
    Lock {
        id: sessionLock
    }

    // The trainable pair. Volume keys move 5 points on the 5% grid;
    // brightness keys move one bar of the 8-step meter (its readout is bars
    // only, so a press always visibly adds or removes one).
    IpcHandler {
        target: "trainable"

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

    // The battle field as the wallpaper, turn 16a. Owns the background
    // layer; hyprpaper is retired.
    Wallpaper {}

    // The 34px HP/PP strip from turn 13b. Always on, event-driven. Its
    // clock is the pointer's way into the calendar page (SUPER + N is the
    // keyboard's).
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

    // The details menu from turn 17a (SUPER + D).
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
