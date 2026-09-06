// Notification toasts, turns 25a and 25k. Top-right stack, newest first, at
// most three visible. Each toast is the frame motif in its tight variant
// (4px window padding, 3px inner panel, 8px drop) with a battle-log line
// inside. Critical toasts trade the outer border for the red and blink at
// 0.4s; they never time out.
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
    // 24px in the design, measured to the frame edge; the soft shadow
    // reaches 12px sideways and 18px down (SoftShadow pad 12, offset 6).
    margins.top: 18
    margins.right: 12

    implicitWidth: 440 + 24
    implicitHeight: stack.implicitHeight + 6 + 18
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "rpg-toasts"

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

                readonly property bool outcome: modelData.resultChip !== undefined
                                                && modelData.resultChip !== ""

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

                // One flat panel straight inside the frame -- the halo and
                // the 5px border are the toast's only rings (the spec's
                // extra inner panel read as border soup at this size).
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
                        spacing: toast.outcome ? 12 : 5

                        // Header: tag chip, then the unread counter (25a) or
                        // the target name (25k).
                        Item {
                            width: parent.width
                            height: tagChip.implicitHeight

                            Chip {
                                id: tagChip
                                label: toast.modelData.tag
                                hue: Skin.categoryColor(toast.modelData.tag)
                            }

                            Text {
                                visible: toast.outcome
                                anchors.left: tagChip.right
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: toast.modelData.target || ""
                                color: Skin.text
                                elide: Text.ElideRight
                                font.family: Skin.fontLabel
                                font.pixelSize: 12
                                font.letterSpacing: 12 * 0.10
                            }

                            Text {
                                visible: !toast.outcome
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.max(1, Notifs.unreadCount - toast.index) + " UNREAD"
                                color: Skin.dim
                                font.family: Skin.fontLabel
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.16
                            }
                        }

                        // 25k result chip.
                        Rectangle {
                            visible: toast.outcome
                            implicitWidth: chipText.implicitWidth + 16
                            implicitHeight: chipText.implicitHeight + 8
                            color: toast.modelData.resultColor || Skin.accent

                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: toast.modelData.resultChip || ""
                                color: Skin.bg
                                font.family: Skin.fontLabel
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.18
                            }
                        }

                        // 25a headline. Outcome toasts have none.
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

                        // 25k dim subline.
                        Text {
                            visible: (toast.modelData.subline || "") !== ""
                            width: parent.width
                            text: toast.modelData.subline || ""
                            color: Skin.dim
                            wrapMode: Text.Wrap
                            lineHeight: 1.6
                            font.family: Skin.fontLabel
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.14
                        }

                        // 25k action buttons (TRY AGAIN / FORGET).
                        Row {
                            visible: !!toast.modelData.actions
                            spacing: 8

                            Repeater {
                                model: toast.modelData.actions || []

                                delegate: Rectangle {
                                    required property var modelData

                                    implicitWidth: actText.implicitWidth + 24
                                    implicitHeight: actText.implicitHeight + 16
                                    color: Skin.cell
                                    border.width: 3
                                    border.color: Skin.inner

                                    Text {
                                        id: actText
                                        anchors.centerIn: parent
                                        text: parent.modelData.label
                                        color: Skin.body
                                        font.family: Skin.fontLabel
                                        font.pixelSize: 10
                                        font.letterSpacing: 10 * 0.16
                                    }

                                    TapHandler {
                                        onTapped: {
                                            const id = toast.modelData.id;
                                            parent.modelData.act();
                                            Notifs.acknowledge(id);
                                        }
                                    }
                                }
                            }
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
