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

    readonly property bool plainField: Skin.variant("field", "plain") !== "creature"

    Rectangle {
        anchors.fill: parent
        // The plain (Console) desk rests on the `bg` void; the creature
        // field keeps its flat `cell` ground under the art.
        color: wall.plainField ? Skin.bg : Skin.cell
    }

    // The plain desk hangs ONE picture -- assets/wallpaper.jpg, the same on
    // every workspace (user call, 2026-08-24: "just the kirby wallpaper
    // instead of the routes"). The per-route art below stays with the
    // creature field, whose whole conceit is that each workspace is a route.
    Image {
        id: plainArt
        visible: wall.plainField && status === Image.Ready
        anchors.fill: parent
        source: wall.assetDir + "wallpaper.jpg"
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
    }

    Image {
        visible: !wall.plainField && status === Image.Ready
        anchors.fill: parent
        source: wall.assetDir + "bg-" + wall.route + ".png"
        fillMode: Image.PreserveAspectCrop
        smooth: false
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

    // ---------------------------------------------------------------- at rest

    // The Console desk at rest: the day of the month as a faint watermark,
    // a short rule, the date in small caps, and the workspace number in the
    // corner. Drawn only on the plain field with no art behind it -- over
    // the picture it would be clutter, and the bar already carries the time.
    Item {
        visible: wall.plainField && !plainArt.visible
        anchors.fill: parent

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -20
            spacing: 14

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(SysState.clock.date, "dd")
                color: Skin.cell
                font.family: Skin.fontLabel
                font.bold: true
                font.pixelSize: 300
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 44
                height: 2
                color: Skin.inner
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(SysState.clock.date, "dddd · MMMM").toUpperCase()
                color: Skin.dim
                font.family: Skin.fontLabel
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.20
            }
        }

        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 22
            anchors.bottomMargin: 18
            text: "Nº " + wall.route
            color: Skin.inner
            font.family: Skin.fontLabel
            font.pixelSize: 10
            font.letterSpacing: 10 * 0.14
        }
    }

    // The creature field keeps the unframed pixel clock top left.
    Column {
        visible: !wall.plainField
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
