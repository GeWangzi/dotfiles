// The status bar. Console dress (2026-08-24): a 32px segmented strip on the
// `shadow` field with a 2px `inner` rule facing the workspace. Cells, left to
// right:
//
//   active workspace (a filled accent block), the other workspaces, the
//   focused window's title -- then wifi (icon + SSID), volume, battery (the
//   icon is the meter), and the date + clock cell.
//
// Status chips (BRN, SUB) stay inline between the halves, only when the
// condition is real and only on a skin that has chips. The species cell
// leads on the creature costume. The battery keeps the fixed threshold
// colours below 20% -- a warning that changes colour with the theme is not
// a warning.
//
// Workspaces returned to the bar with the Console redesign (they left in the
// HP-strip era); SUPER+number still switches, the cells are the readout.

import QtQuick
import Quickshell
import Quickshell.Hyprland

PanelWindow {
    id: bar

    // The clock opens the calendar page, which is the other half of how that
    // surface is reached (the keybind is SUPER + N).
    signal clockActivated()

    // The 1px rule between the right-hand cells.
    component CellRule: Rectangle {
        width: 1
        height: parent.height
        color: Skin.inner
    }

    readonly property bool atBottom: Skin.barEdge === "bottom"

    readonly property int activeWs:
        Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace
            ? Hyprland.focusedMonitor.activeWorkspace.id : 1

    // Existing workspace ids, sorted. Special workspaces have negative ids
    // and stay off the bar.
    readonly property var wsIds: {
        const out = [];
        const all = Hyprland.workspaces.values;
        for (let i = 0; i < all.length; i++)
            if (all[i].id > 0) out.push(all[i].id);
        out.sort((a, b) => a - b);
        return out;
    }

    readonly property string windowTitle:
        Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""

    anchors {
        top: !bar.atBottom
        bottom: bar.atBottom
        left: true
        right: true
    }
    implicitHeight: 32
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: Skin.shadow

        // The 2px rule, on whichever edge faces the workspace.
        Rectangle {
            y: bar.atBottom ? 0 : parent.height - 2
            width: parent.width
            height: 2
            color: Skin.inner
        }

        readonly property int contentY: bar.atBottom ? 2 : 0
        readonly property int contentH: height - 2

        // ---- left: workspaces, title, chips
        Row {
            id: content
            y: parent.contentY
            height: parent.contentH

            // Active workspace: the one filled cell on the bar.
            Rectangle {
                width: wsText.implicitWidth + 24
                height: parent.height
                color: Skin.snd

                Text {
                    id: wsText
                    anchors.centerIn: parent
                    text: "WS " + bar.activeWs
                    color: Skin.shadow
                    font.family: Skin.fontLabel
                    font.bold: true
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.10
                }
            }

            // The other workspaces, as a quiet cell.
            Item {
                visible: bar.wsIds.length > 1
                width: otherWs.implicitWidth + 24
                height: parent.height

                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: Skin.inner
                }

                Text {
                    id: otherWs
                    anchors.centerIn: parent
                    text: bar.wsIds.filter(n => n !== bar.activeWs).join(" ")
                    color: Skin.dim
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.14
                }
            }

            // Focused window title.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 12
                width: Math.min(implicitWidth, 420)
                text: bar.windowTitle
                color: Skin.dim
                elide: Text.ElideRight
                font.family: Skin.fontLabel
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.06
            }
        }

        // ---- right: wifi, volume, battery, clock -- ruled cells
        Row {
            id: rightSide
            anchors.right: parent.right
            y: parent.contentY
            height: parent.contentH

            CellRule {}

            Row {
                height: parent.height
                spacing: 7
                leftPadding: 12
                rightPadding: 12

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "wifi"
                    size: 14
                    color: SysState.wifiUp ? Skin.dim : Skin.critical
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: SysState.wifiUp
                        ? (SysState.ssid !== "" ? SysState.ssid.toUpperCase() : "WIFI")
                        : "NO LINK"
                    color: SysState.wifiUp ? Skin.body : Skin.critical
                    font.family: Skin.fontLabel
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.10
                }
            }

            CellRule {}

            Row {
                height: parent.height
                spacing: 7
                leftPadding: 12
                rightPadding: 12

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "vol"
                    size: 14
                    color: Skin.dim
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: SysState.volPct
                    color: Skin.text
                    font.family: Skin.fontLabel
                    font.bold: true
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.08
                }
            }

            CellRule {}

            Row {
                height: parent.height
                spacing: 7
                leftPadding: 12
                rightPadding: 12

                BatteryIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    fraction: SysState.battery
                    color: Skin.dim
                    fillColor: Skin.levelColor(SysState.battery)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(SysState.battery * 100)
                          + (SysState.charging ? " CHG" : "")
                    color: SysState.battery <= 0.2 ? Skin.critical : Skin.text
                    font.family: Skin.fontLabel
                    font.bold: true
                    font.pixelSize: 10
                    font.letterSpacing: 10 * 0.08
                }
            }

            CellRule {}

            // Date + clock cell, on the `cell` fill. Opens the calendar page.
            Rectangle {
                width: clockRow.implicitWidth + 24
                height: parent.height
                color: clockHover.hovered ? Skin.window : Skin.cell

                Row {
                    id: clockRow
                    anchors.centerIn: parent
                    spacing: 8

                    // One size for both: the 10px date under the 12px bold
                    // clock read as a single garbled string. Hierarchy comes
                    // from weight and colour alone.
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: SysState.date
                        color: Skin.body
                        font.family: Skin.fontLabel
                        font.pixelSize: 12
                        font.letterSpacing: 12 * 0.06
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: SysState.time
                        color: clockHover.hovered ? Skin.snd : Skin.text
                        font.family: Skin.fontLabel
                        font.bold: true
                        font.pixelSize: 12
                    }
                }

                HoverHandler { id: clockHover }
                TapHandler { onTapped: bar.clockActivated() }
            }
        }
    }
}
