// The launcher, reworked to turn 14a of the creature-shell handoff: the move
// bar. The machine's four favourite apps are its moves; launching one is
// using it. With no query the surface is only the bottom band of the battle
// screen -- a log box asking `What will GRIMLING do?` plus a 2x2 command box
// with PP per move. Typing switches to the list mode from 15f: a query line
// where the log box sits and truncating result rows below it.
//
// Departures from the design document, all deliberate:
//
//   - It floats over the live desktop rather than sitting in a full battle
//     screen; the field became the wallpaper (turn 16a) and the launcher
//     kept only the band.
//   - PP is real: a move's meter is the machine's RAM not spent on that app,
//     out of the machine's total in GB (an IV -- fixed at birth). An app
//     that is not running has full PP. The design left PP unmapped.
//   - Every Silkscreen size is rounded up to even, because the face is a
//     pixel font and this panel runs at scale 1.5. See fonts/README.md.
//
// The blinking ▼ in the log box is the only ▼ in the system.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win

    signal dismissed()

    property string query: ""
    property int page: 0
    property int selected: 0

    readonly property bool listMode: query !== ""

    readonly property int perPage: listMode ? 6 : 4
    readonly property var results: Apps.search(query)
    readonly property int pageCount: Math.max(1, Math.ceil(results.length / perPage))
    readonly property var pageItems: results.slice(page * perPage, page * perPage + perPage)
    readonly property var current: pageItems.length > 0
        ? pageItems[Math.min(selected, pageItems.length - 1)]
        : null

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore

    // Transparent: only the frame and its shadow paint. The surface still
    // covers the screen, which is what lets it take keyboard focus and treat
    // a click anywhere outside the frame as a dismissal.
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "rpg-launcher"

    onVisibleChanged: {
        // Sampling the process table is gated on the launcher being on screen.
        Apps.polling = visible;
        if (visible) {
            query = "";
            page = 0;
            selected = 0;
            keys.forceActiveFocus();
        }
    }

    function launch() {
        if (!current) return;
        Apps.launch(current);
        win.dismissed();
    }

    // Move-bar mode is a 2x2 grid; list mode is a single column. Both stop at
    // the edges and page rather than wrap.
    function move(dx, dy) {
        if (listMode) {
            const next = selected + dy;
            if (next < 0) {
                if (page > 0) { page--; selected = perPage - 1; }
            } else if (next >= pageItems.length) {
                if (page < pageCount - 1) { page++; selected = 0; }
            } else {
                selected = next;
            }
            return;
        }

        const col = selected % 2;
        const row = Math.floor(selected / 2);
        if (dx !== 0) {
            const nextCol = Math.min(1, Math.max(0, col + dx));
            selected = Math.min(pageItems.length - 1, row * 2 + nextCol);
        } else {
            const nextRow = Math.min(1, Math.max(0, row + dy));
            selected = Math.min(pageItems.length - 1, nextRow * 2 + col);
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        TapHandler {
            onTapped: win.dismissed()
        }

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Left:    win.move(-1, 0); break;
            case Qt.Key_Right:   win.move(1, 0); break;
            case Qt.Key_Up:      win.move(0, -1); break;
            case Qt.Key_Down:    win.move(0, 1); break;
            case Qt.Key_Return:
            case Qt.Key_Enter:   win.launch(); break;
            case Qt.Key_Escape:
                // Escape backs out of the search before it closes the
                // launcher, so a mistyped query costs one keystroke.
                if (win.query !== "") {
                    win.query = "";
                    win.page = 0;
                    win.selected = 0;
                } else {
                    win.dismissed();
                }
                break;
            case Qt.Key_Backspace:
                win.query = win.query.slice(0, -1);
                win.page = 0;
                win.selected = 0;
                break;
            case Qt.Key_PageDown:
                if (win.page < win.pageCount - 1) { win.page++; win.selected = 0; }
                break;
            case Qt.Key_PageUp:
                if (win.page > 0) { win.page--; win.selected = 0; }
                break;
            default:
                // Number keys switch skin, but only when they are not part of
                // a query. 1-9 are the first nine, 0 is the tenth, and the
                // eleventh is one PgDn-free `skinctl next` away.
                if (win.query === "" && event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                    const n = event.key === Qt.Key_0 ? 10 : event.key - Qt.Key_0;
                    Quickshell.execDetached([
                        Quickshell.env("HOME") + "/.local/bin/skinctl",
                        "set",
                        String(n)
                    ]);
                    break;
                }
                if (event.text && event.text.length === 1 && event.text >= " ") {
                    win.query += event.text;
                    win.page = 0;
                    win.selected = 0;
                    break;
                }
                return;
            }
            event.accepted = true;
        }

        Frame {
            id: frame

            width: 1200
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 42

            // The band's own padding is the design's 12px, not the Frame
            // default panel padding.
            padTop: 12
            padSide: 12
            padBottom: 12

            title: win.listMode ? "SEARCH" : Skin.menuWord

            TapHandler {
                onTapped: {}
            }

            // ---------------- move bar (no query)
            Row {
                visible: !win.listMode
                width: parent.width
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
                            font.family: "DotGothic16"
                            font.pixelSize: 18
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            width: parent.width
                            text: win.current && win.current.description !== ""
                                ? win.current.description : "No description."
                            color: Skin.body
                            font.family: "DotGothic16"
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
                        text: win.current
                            ? win.current.tag + " · " + Apps.statusFor(win.current.match)
                            : ""
                        color: Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.14
                    }

                    // The only ▼ in the system.
                    Blink {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        width: advance.implicitWidth
                        height: advance.implicitHeight

                        Text {
                            id: advance
                            text: "▼"
                            color: Skin.accent
                            font.family: "Silkscreen"
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
                            model: win.listMode ? [] : win.pageItems

                            Rectangle {
                                id: moveCell

                                required property int index
                                required property var modelData

                                readonly property bool active: win.selected === index

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
                                        font.family: "Silkscreen"
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
                                            font.family: "Silkscreen"
                                            font.pixelSize: 10
                                            font.letterSpacing: 10 * 0.18
                                        }

                                        Text {
                                            anchors.right: parent.right
                                            text: Apps.ppFor(moveCell.modelData.match)
                                            color: Skin.dim
                                            font.family: "Silkscreen"
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
                                        win.selected = moveCell.index;
                                        win.launch();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------------- list mode (typing)
            Column {
                visible: win.listMode
                width: parent.width
                spacing: 10

                // Query line where the log box sits.
                Rectangle {
                    width: parent.width
                    height: queryRow.implicitHeight + 24
                    color: Skin.strip
                    border.width: 4
                    border.color: Skin.inner

                    Row {
                        id: queryRow
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 9

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "▸"
                            color: Skin.accent
                            font.family: "Silkscreen"
                            font.pixelSize: 12
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.query
                            color: Skin.text
                            font.family: "DotGothic16"
                            font.pixelSize: 18
                        }

                        Blink {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 9
                            height: 18

                            Rectangle {
                                width: 9
                                height: 18
                                color: Skin.accent
                            }
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: (win.results.length === 0 ? 0 : win.page * win.perPage + win.selected + 1)
                              + " OF " + win.results.length
                        color: Skin.dim
                        font.family: "Silkscreen"
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.12
                    }
                }

                // Result rows: 44px tag column, truncating name, status.
                Repeater {
                    model: win.listMode ? win.pageItems : []

                    Rectangle {
                        id: row

                        required property int index
                        required property var modelData

                        readonly property bool active: win.selected === index

                        width: parent.width
                        height: 42
                        color: Skin.cell

                        Text {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.tag
                            color: Skin.categoryColor(row.modelData.tag)
                            font.family: "Silkscreen"
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.16
                        }

                        Text {
                            x: 66
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 66 - 130
                            text: row.modelData.name
                            color: Skin.text
                            font.family: "Silkscreen"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: Apps.windowsFor(row.modelData.match) > 0 ? "RUNNING" : ""
                            color: Skin.dim
                            font.family: "Silkscreen"
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.10
                        }

                        Rectangle {
                            visible: row.active
                            anchors.fill: parent
                            color: "transparent"
                            border.width: 3
                            border.color: Skin.outline
                        }

                        TapHandler {
                            onTapped: {
                                win.selected = row.index;
                                win.launch();
                            }
                        }
                    }
                }

                // Nothing matched: the creature's empty word (15f).
                Rectangle {
                    visible: win.pageItems.length === 0
                    width: parent.width
                    height: 96
                    color: Skin.cell

                    Column {
                        anchors.centerIn: parent
                        spacing: 10

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Skin.emptyWord
                            color: Skin.text
                            font.family: "Silkscreen"
                            font.pixelSize: 14
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Nothing installed matches that."
                            color: Skin.body
                            font.family: "DotGothic16"
                            font.pixelSize: 16
                        }
                    }
                }
            }
        }
    }
}
