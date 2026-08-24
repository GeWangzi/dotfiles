// The desktop wallpaper: per-workspace background image and the unframed
// clock top left with hard pixel drop shadows. This surface replaces
// hyprpaper: it owns the background layer and paints itself. Workspace n
// draws assets/bg-<n>.png (gitignored art); a missing background falls back
// to flat `cell`.
//
// The battle-field furniture -- foe and ally plates, sprite slots -- is the
// creature costume's half of this surface (CreatureField.qml), loaded only
// when the skin's `field` variant says "creature". The plain shell never
// constructs it.

import QtQuick
import Quickshell
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

    // ---------------------------------------------------------------- creature field

    // The costume's furniture, constructed only when the skin asks for it.
    Loader {
        anchors.fill: parent
        active: Skin.variant("field", "plain") === "creature"
        sourceComponent: CreatureField {
            assetDir: wall.assetDir
            bare: wall.bare
            route: wall.route
        }
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

            // Which workspace this is -- each one is its own route. Costume
            // furniture: the plain shell tells workspaces apart by their
            // background art alone.
            WidgetText {
                visible: Skin.has("route")
                text: "ROUTE " + wall.route
                size: 12
                tracking: 12 * 0.2
            }
        }

    }
}
