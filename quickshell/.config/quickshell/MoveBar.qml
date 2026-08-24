// The launcher's no-query furniture, from turn 14a of the creature-shell
// handoff: the dialogue log box asking what the creature will do, and the
// 2x2 command grid of running moves with their PP. This is the costume half
// of Launcher.qml -- loaded only when the skin's `idle` variant says
// "moves", so the plain launcher idles as a bare search line instead. All
// selection state and the launch path live in Launcher.qml and are shared;
// this file only renders them.

import QtQuick

Row {
    id: bar

    // The Launcher window: selection, paging and launch live there.
    required property var win

    spacing: 12

    // Log box, 1.3fr of the band.
    Rectangle {
        id: logBox
        width: (parent.width - 12) * 1.3 / 2.3
        height: commandBox.height
        color: Skin.strip
        border.width: 4
        border.color: Skin.inner

        Column {
            x: 20
            y: 18
            width: parent.width - 40
            spacing: 10

            Text {
                width: parent.width
                text: "What will " + Skin.species + " do?"
                color: Skin.text
                font.family: Skin.fontBody
                font.pixelSize: 18
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: bar.win && bar.win.current && bar.win.current.description !== ""
                    ? bar.win.current.description : "No description."
                color: Skin.body
                font.family: Skin.fontBody
                font.pixelSize: 16
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        Text {
            x: 20
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            text: bar.win && bar.win.current
                ? bar.win.current.tag + " · " + Apps.statusFor(bar.win.current.match)
                : ""
            color: Skin.dim
            font.family: Skin.fontLabel
            font.pixelSize: 10
            font.letterSpacing: 10 * 0.14
        }

        // The log box advance marker.
        Blink {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            width: advance.implicitWidth
            height: advance.implicitHeight

            Text {
                id: advance
                text: Skin.glyphMore
                color: Skin.accent
                font.family: Skin.fontLabel
                font.pixelSize: 14
            }
        }
    }

    // 2x2 command box.
    Rectangle {
        id: commandBox
        width: (parent.width - 12) * 1 / 2.3
        height: moveGrid.height + 24
        color: Skin.strip
        border.width: 4
        border.color: Skin.inner

        Grid {
            id: moveGrid
            x: 8
            y: 8
            columns: 2
            columnSpacing: 8
            rowSpacing: 8

            readonly property int cellWidth:
                (commandBox.width - 16 - 8 - 8) / 2

            Repeater {
                model: !bar.win || bar.win.listMode ? [] : bar.win.pageItems

                Rectangle {
                    id: moveCell

                    required property int index
                    required property var modelData

                    readonly property bool active: bar.win && bar.win.selected === index

                    width: moveGrid.cellWidth
                    height: 64
                    color: Skin.cell

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 14
                        width: parent.width - 28
                        spacing: 5

                        Text {
                            width: parent.width
                            text: moveCell.modelData.name
                            color: Skin.text
                            font.family: Skin.fontLabel
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }

                        Item {
                            width: parent.width
                            height: tagText.implicitHeight

                            Text {
                                id: tagText
                                text: moveCell.modelData.tag
                                color: Skin.categoryColor(moveCell.modelData.tag)
                                font.family: Skin.fontLabel
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.18
                            }

                            Text {
                                anchors.right: parent.right
                                text: Apps.ppFor(moveCell.modelData.match)
                                color: Skin.dim
                                font.family: Skin.fontLabel
                                font.pixelSize: 10
                                font.letterSpacing: 10 * 0.12
                            }
                        }
                    }

                    // Selection is the outline only -- no per-cell
                    // cursor glyph in the command box (turn 14a).
                    Rectangle {
                        visible: moveCell.active
                        anchors.fill: parent
                        color: "transparent"
                        border.width: 3
                        border.color: Skin.outline
                    }

                    HoverHandler { id: moveHover }
                    TapHandler {
                        onTapped: {
                            bar.win.selected = moveCell.index;
                            bar.win.launch();
                        }
                    }
                }
            }
        }
    }
}
