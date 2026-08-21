// Notification history -- the BATTLE LOG, turn 25c. Everything that
// happened, grouped by calendar day into TODAY / YESTERDAY / EARLIER.
// Opening it marks everything read (the toasts' UNREAD counters and the
// suppressed SUB backlog both resolve here).
//
// Same overlay shape as the power menu: fullscreen transparent window,
// exclusive keyboard, Esc or an outside click dismisses.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win

    signal dismissed()

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "rpg-battlelog"

    onVisibleChanged: {
        if (visible) {
            Notifs.markAllRead();
            logScroll.contentY = 0;
            keys.forceActiveFocus();
        }
    }

    // events -> [{ title, rows: [{ ev, when }] }] in TODAY / YESTERDAY /
    // EARLIER order. Recomputed when the event list is reassigned.
    readonly property var groups: {
        const now = new Date();
        const startToday = new Date(now.getFullYear(), now.getMonth(),
                                    now.getDate()).getTime();
        const startYesterday = startToday - 86400000;
        const months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                        "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        const out = [{ title: "TODAY", rows: [] },
                     { title: "YESTERDAY", rows: [] },
                     { title: "EARLIER", rows: [] }];
        Notifs.events.forEach(ev => {
            const d = new Date(ev.ts);
            const hm = ("0" + d.getHours()).slice(-2) + ":"
                     + ("0" + d.getMinutes()).slice(-2);
            if (ev.ts >= startToday)
                out[0].rows.push({ ev: ev, when: hm });
            else if (ev.ts >= startYesterday)
                out[1].rows.push({ ev: ev, when: hm });
            else
                out[2].rows.push({ ev: ev,
                    when: d.getDate() + " " + months[d.getMonth()] });
        });
        return out.filter(g => g.rows.length > 0);
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        TapHandler {
            onTapped: eventPoint => {
                const p = logFrame.mapFromItem(keys,
                    eventPoint.position.x, eventPoint.position.y);
                if (p.x < 0 || p.y < 0 || p.x > logFrame.width || p.y > logFrame.height)
                    win.dismissed();
            }
        }

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Escape:
                win.dismissed();
                event.accepted = true;
                break;
            case Qt.Key_Up:
            case Qt.Key_K:
                logScroll.contentY = Math.max(0, logScroll.contentY - 72);
                event.accepted = true;
                break;
            case Qt.Key_Down:
            case Qt.Key_J:
                logScroll.contentY = Math.max(0,
                    Math.min(logScroll.contentHeight - logScroll.height,
                             logScroll.contentY + 72));
                event.accepted = true;
                break;
            }
        }

        Frame {
            id: logFrame
            anchors.centerIn: parent
            width: win.groups.length === 0 ? 380 : 700
            padTop: 24
            padSide: 12
            padBottom: 12
            title: "BATTLE LOG"

            // Empty variant: NO DATA.
            Column {
                visible: win.groups.length === 0
                width: logFrame.width - 2 * (5 + 12)
                height: visible ? implicitHeight : 0
                topPadding: 36
                bottomPadding: 40
                spacing: 10

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Skin.emptyWord
                    color: Skin.dim
                    font.family: "Silkscreen"
                    font.pixelSize: 14
                    font.letterSpacing: 14 * 0.18
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Nothing has happened yet."
                    color: Skin.dim
                    font.family: "DotGothic16"
                    font.pixelSize: 16
                }
            }

            Flickable {
                id: logScroll
                visible: win.groups.length > 0
                width: logFrame.width - 2 * (5 + 12)
                height: visible ? Math.min(entries.implicitHeight, 520) : 0
                contentWidth: width
                contentHeight: entries.implicitHeight
                clip: true
                interactive: contentHeight > height

                Column {
                    id: entries
                    width: logScroll.width
                    spacing: 12

                    Repeater {
                        model: win.groups

                        delegate: Column {
                            required property var modelData

                            width: entries.width
                            spacing: 8

                            // Group header: label + rule.
                            Item {
                                width: parent.width
                                height: groupLabel.implicitHeight

                                Text {
                                    id: groupLabel
                                    text: parent.parent.modelData.title
                                    color: Skin.dim
                                    font.family: "Silkscreen"
                                    font.pixelSize: 10
                                    font.letterSpacing: 10 * 0.20
                                }

                                Rectangle {
                                    anchors.left: groupLabel.right
                                    anchors.leftMargin: 12
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 3
                                    color: Skin.inner
                                }
                            }

                            Repeater {
                                model: parent.modelData.rows

                                delegate: Rectangle {
                                    required property var modelData

                                    width: entries.width
                                    height: 42
                                    color: Skin.strip
                                    border.width: 3
                                    border.color: Skin.inner

                                    Chip {
                                        id: rowChip
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        label: parent.modelData.ev.tag
                                        hue: Skin.categoryColor(parent.modelData.ev.tag)
                                    }

                                    Text {
                                        anchors.left: rowChip.right
                                        anchors.leftMargin: 12
                                        anchors.right: rowWhen.left
                                        anchors.rightMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.modelData.ev.headline
                                              || parent.modelData.ev.body
                                        color: Skin.text
                                        elide: Text.ElideRight
                                        font.family: "Silkscreen"
                                        font.pixelSize: 12
                                        font.letterSpacing: 12 * 0.06
                                    }

                                    Text {
                                        id: rowWhen
                                        anchors.right: parent.right
                                        anchors.rightMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.modelData.when
                                        color: Skin.dim
                                        font.family: "Silkscreen"
                                        font.pixelSize: 10
                                        font.letterSpacing: 10 * 0.12
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
