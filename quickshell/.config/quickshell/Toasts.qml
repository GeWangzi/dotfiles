// Notification toasts. Top-right stack, newest first, at most three
// visible. Each toast is the frame motif with a tag chip, the unread count,
// the headline and the application's own body line inside. Critical toasts
// trade the border for red and never time out.
//
// The window exists only while something is presented, so an idle desktop
// pays nothing for this surface. No keyboard focus -- a toast is clicked or
// it expires.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win

    visible: Notifs.presented.length > 0

    anchors.top: true
    anchors.right: true
    margins.top: 24
    margins.right: 24

    implicitWidth: 440
    implicitHeight: stack.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-toasts"

    Column {
        id: stack
        x: 12
        y: 6
        spacing: 12

        Repeater {
            model: Notifs.presented.slice(0, 3)

            delegate: Frame {
                id: toast

                required property var modelData
                required property int index

                width: 440
                height: panel.height + 2 * frameBorder + stripHeight
                padTop: 0
                padSide: 0
                padBottom: 0
                borderColor: modelData.critical ? Skin.critical : Skin.inner

                // Non-critical, non-actionable toasts expire on their own.
                Timer {
                    interval: toast.modelData.timeout
                    running: !toast.modelData.critical && toast.modelData.timeout > 0
                    onTriggered: Notifs.acknowledge(toast.modelData.id)
                }

                // One flat panel straight inside the frame.
                Rectangle {
                    id: panel
                    width: 440 - 2 * frameBorder
                    height: content.implicitHeight + 10 + 14
                    color: "transparent"

                    Column {
                        id: content
                        x: 14
                        y: 10
                        width: parent.width - 28
                        spacing: 5

                        // Header: tag chip, then the unread counter.
                        Item {
                            width: parent.width
                            height: tagChip.implicitHeight

                            Chip {
                                id: tagChip
                                label: toast.modelData.tag
                                hue: Skin.categoryColor(toast.modelData.tag)
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.max(1, Notifs.unreadCount - toast.index) + " UNREAD"
                                color: Skin.dim
                                font.family: Skin.fontLabel
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.16
                            }
                        }

                        // Headline.
                        Text {
                            visible: text !== ""
                            width: parent.width
                            text: toast.modelData.headline
                            color: Skin.text
                            wrapMode: Text.Wrap
                            lineHeight: 1.35
                            font.family: Skin.fontLabel
                            font.pixelSize: 20   // 19 in the design; even rule
                            font.letterSpacing: 20 * 0.04
                        }

                        // Body / log line: always the plain text.
                        Text {
                            visible: text !== ""
                            width: parent.width
                            text: toast.modelData.body
                            color: Skin.body
                            wrapMode: Text.Wrap
                            font.family: Skin.fontBody
                            font.pixelSize: 16
                        }
                    }

                    TapHandler {
                        onTapped: Notifs.acknowledge(toast.modelData.id)
                    }
                }
            }
        }
    }
}
