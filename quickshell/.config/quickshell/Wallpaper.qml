// The desktop wallpaper: one picture, the same on every workspace. This
// surface replaces hyprpaper: it owns the background layer and paints
// itself. The picture is assets/wallpaper.jpg (gitignored, set with
// `skinctl wallpaper <image>`); until one is set the desk is the flat `bg`
// void, the same fallback the lock screen has.

import QtQuick
import Quickshell
import Quickshell.Wayland

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
    WlrLayershell.namespace: "shell-wallpaper"

    Rectangle {
        anchors.fill: parent
        color: Skin.bg
    }

    Image {
        visible: status === Image.Ready
        anchors.fill: parent
        source: Quickshell.env("HOME") + "/.config/quickshell/assets/wallpaper.jpg"
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
    }
}
