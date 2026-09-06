// The launcher. With no query it is a bare search line with a blinking
// cursor, and typing brings the result list (a query line and truncating
// result rows below it). It floats over the live desktop as one band.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: win

    signal dismissed()

    property string query: ""
    property int page: 0
    property int selected: 0

    // "apps" is the search; "clip" and "glyphs" are the list modes, opened
    // via `qs ipc call launcher clipboard` and `... glyphs`. In those modes
    // the query line is a filter and the digits are literal text.
    property string mode: "apps"
    readonly property bool altMode: mode !== "apps"

    function openAs(m) {
        if (mode === m) return;
        mode = m;
        // Re-targeting an already-open launcher (SUPER+V while the search
        // line is up) never passes through onVisibleChanged, so reset here too.
        if (visible) {
            query = "";
            page = 0;
            selected = 0;
            if (mode === "clip") clipQuery.running = true;
        }
    }

    readonly property bool listMode: mode === "apps" && query !== ""

    // Idle: no query. The launcher shows just the search line; selection
    // and Enter are inert until typing starts, because there is nothing on
    // screen to select.
    readonly property bool plainIdle: mode === "apps" && query === ""

    readonly property int perPage: listMode ? 6 : 4
    readonly property var results: Apps.search(query)
    readonly property int pageCount: Math.max(1, Math.ceil(results.length / perPage))
    readonly property var pageItems: results.slice(page * perPage, page * perPage + perPage)
    readonly property var current: pageItems.length > 0
        ? pageItems[Math.min(selected, pageItems.length - 1)]
        : null

    // ---------------- clip / glyph sources (25d/25e)

    // cliphist rows, fetched when the clipboard mode opens. Each line of
    // `cliphist list` is "<id>\t<preview>".
    property var clipEntries: []

    // Image entries list as "[[ binary data 948 KiB png 1920x1080 ]]"; those
    // rows render a thumbnail instead. Thumbs are cached under
    // ~/.cache/cliphist/thumbs (id-keyed, so existing files are reused,
    // never re-decoded).
    readonly property string thumbDir:
        (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache")
        + "/cliphist/thumbs"
    property bool thumbsReady: false

    function isImgPreview(preview) {
        return /binary data .* (png|jpe?g|gif|bmp)/.test(preview);
    }

    Process {
        id: clipQuery
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                win.clipEntries = this.text.split("\n")
                    .filter(l => l.length > 0)
                    .map(l => {
                        const cut = l.indexOf("\t");
                        return cut < 0
                            ? { cid: l, preview: l }
                            : { cid: l.slice(0, cut), preview: l.slice(cut + 1) };
                    });

                const imgs = win.clipEntries
                    .filter(e => win.isImgPreview(e.preview))
                    .map(e => e.cid)
                    .filter(id => /^\d+$/.test(id));
                win.thumbsReady = false;
                if (imgs.length === 0) {
                    win.thumbsReady = true;
                    return;
                }
                thumbProc.command = ["sh", "-c",
                    'mkdir -p "$0"; for id in ' + imgs.join(" ") + '; do'
                    + ' [ -f "$0/$id.png" ] || cliphist decode "$id" > "$0/$id.png";'
                    + ' done', win.thumbDir];
                thumbProc.running = true;
            }
        }
    }

    Process {
        id: thumbProc
        onExited: win.thumbsReady = true
    }

    // The design's 32 glyphs, with hand keywords so the filter query
    // ("arrow") finds them.
    readonly property var glyphSet: [
        { ch: "▸", k: "triangle right cursor arrow" },
        { ch: "▼", k: "triangle down arrow advance" },
        { ch: "▲", k: "triangle up arrow" },
        { ch: "❯", k: "chevron right arrow prompt" },
        { ch: "⑂", k: "fork branch git" },
        { ch: "★", k: "star favourite" },
        { ch: "✔", k: "check tick yes" },
        { ch: "✘", k: "cross ballot no" },
        { ch: "·", k: "middle dot bullet separator" },
        { ch: "—", k: "em dash line" },
        { ch: "◆", k: "diamond filled" },
        { ch: "⬥", k: "diamond small" },
        { ch: "⧗", k: "hourglass time wait" },
        { ch: "⧉", k: "boxes copy window" },
        { ch: "⌬", k: "benzene ring hex" },
        { ch: "⟡", k: "diamond outline lozenge" },
        { ch: "⟢", k: "arrow tail right" },
        { ch: "⇧", k: "shift up arrow" },
        { ch: "↵", k: "return enter newline arrow" },
        { ch: "⌫", k: "backspace delete erase arrow" },
        { ch: "§", k: "section paragraph legal" },
        { ch: "†", k: "dagger cross footnote" },
        { ch: "∴", k: "therefore three dots" },
        { ch: "≈", k: "almost equal approx wave tilde" },
        { ch: "∞", k: "infinity loop forever" },
        { ch: "⌘", k: "command cmd mac key" },
        { ch: "⌥", k: "option alt mac key" },
        { ch: "☰", k: "menu hamburger trigram lines" },
        { ch: "⣿", k: "braille full block" },
        { ch: "⠿", k: "braille dots six" },
        { ch: "▚", k: "quadrant checker block" },
        { ch: "▞", k: "quadrant checker block" }
    ]

    readonly property var altResults: {
        const q = query.toLowerCase();
        if (mode === "clip")
            return q === "" ? clipEntries
                : clipEntries.filter(e => e.preview.toLowerCase().includes(q));
        if (mode === "glyphs")
            return q === "" ? glyphSet
                : glyphSet.filter(g => g.k.includes(q));
        return [];
    }

    // Clipboard rows slide an 8-row window under the selection instead of
    // paging, so the outline can sit mid-list (25d).
    readonly property int altWindow: 8
    readonly property int altStart: mode === "clip"
        ? Math.max(0, Math.min(selected - 3, altResults.length - altWindow))
        : 0
    readonly property var altItems: mode === "clip"
        ? altResults.slice(altStart, altStart + altWindow)
        : altResults

    // Enter means "put this here", not "put this on the clipboard": the row
    // is copied and then pasted into whatever had focus before the launcher
    // opened. paste-to-focus waits for this surface to release its keyboard
    // grab and picks CTRL+V or CTRL+SHIFT+V by window class. The clipboard is
    // still filled either way, so a paste that lands nowhere loses nothing.
    function altActivate() {
        const item = altResults[Math.min(selected, altResults.length - 1)];
        if (!item) return;
        const paste = ' && "$HOME/.local/bin/paste-to-focus"';
        if (mode === "clip")
            Quickshell.execDetached(["sh", "-c",
                "cliphist decode " + item.cid + " | wl-copy" + paste]);
        else
            Quickshell.execDetached(["sh", "-c",
                'printf %s "$1" | wl-copy' + paste, "sh", item.ch]);
        win.dismissed();
    }

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
        if (visible) {
            query = "";
            page = 0;
            selected = 0;
            if (mode === "clip") clipQuery.running = true;
            keys.forceActiveFocus();
        }
    }

    function launch() {
        if (win.plainIdle) return;
        if (!current) return;
        Apps.launch(current);
        win.dismissed();
    }

    // Move-bar mode is a 2x2 grid; list mode is a single column. Both stop at
    // the edges and page rather than wrap. Clip is a sliding column over the
    // full result list; glyphs an 8-wide grid.
    function move(dx, dy) {
        if (win.plainIdle) return;
        if (mode === "clip") {
            selected = Math.max(0, Math.min(altResults.length - 1, selected + dy));
            return;
        }
        if (mode === "glyphs") {
            const next = selected + dx + dy * 8;
            selected = Math.max(0, Math.min(altResults.length - 1, next));
            return;
        }
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

        // Dismiss only on a click outside the frame (the empty TapHandler on
        // the frame takes no exclusive grab, so it never swallowed clicks).
        TapHandler {
            onTapped: eventPoint => {
                const p = frame.mapFromItem(keys,
                    eventPoint.position.x, eventPoint.position.y);
                if (p.x < 0 || p.y < 0 || p.x > frame.width || p.y > frame.height)
                    win.dismissed();
            }
        }

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Left:    win.move(-1, 0); break;
            case Qt.Key_Right:   win.move(1, 0); break;
            case Qt.Key_Up:      win.move(0, -1); break;
            case Qt.Key_Down:    win.move(0, 1); break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (win.altMode) win.altActivate(); else win.launch();
                break;
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
                // a query and only on the move bar -- in the clip/glyph modes
                // a digit is filter text. Key n is the nth skin in the TOML;
                // a number past the end of the roster is a silent no-op.
                if (!win.altMode && win.query === ""
                        && event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
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

            width: win.altMode ? 1000 : 1200
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 42

            // The band's own padding is the design's 12px, not the Frame
            // default panel padding.
            padTop: 12
            padSide: 12
            padBottom: 12

            title: win.mode === "clip" ? "CLIPBOARD"
                 : win.mode === "glyphs" ? "GLYPHS"
                 : win.listMode ? "SEARCH" : Skin.menuWord

            // ---------------- list mode (typing), and the idle's bare
            // search line
            Column {
                visible: win.listMode || win.plainIdle
                width: parent.width
                spacing: 10

                // Query line where the log box sits: a bare row over a
                // 1px rule (Console dress), the search icon as the prompt.
                Rectangle {
                    width: parent.width
                    height: queryRow.implicitHeight + 24
                    color: "transparent"

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Skin.inner
                    }

                    Row {
                        id: queryRow
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "search"
                            size: 14
                            color: Skin.accent
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.query
                            color: Skin.text
                            font.family: Skin.fontBody
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
                        visible: win.listMode
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: (win.results.length === 0 ? 0 : win.page * win.perPage + win.selected + 1)
                              + " OF " + win.results.length
                        color: Skin.dim
                        font.family: Skin.fontLabel
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.12
                    }

                    // The plain idle's only furniture: a hint where the
                    // count sits in list mode.
                    Text {
                        visible: win.plainIdle
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "TYPE TO SEARCH"
                        color: Skin.dim
                        font.family: Skin.fontLabel
                        font.pixelSize: 10
                        font.letterSpacing: 10 * 0.12
                    }
                }

                // Result rows, Console dress: a two-digit index, the name,
                // the category tag at the right, RUNNING past it. The
                // selected row is a filled block with the index in accent --
                // no outline.
                Repeater {
                    model: win.listMode ? win.pageItems : []

                    Rectangle {
                        id: row

                        required property int index
                        required property var modelData

                        readonly property bool active: win.selected === index

                        width: parent.width
                        height: 42
                        color: active ? Skin.window : "transparent"

                        Text {
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: (row.index + 1 < 10 ? "0" : "") + (row.index + 1)
                            color: row.active ? Skin.snd : Skin.dim
                            font.family: Skin.fontLabel
                            font.bold: row.active
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.10
                        }

                        Text {
                            x: 52
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 52 - 200
                            text: row.modelData.name
                            color: row.active ? Skin.text : Skin.body
                            font.family: Skin.fontLabel
                            font.bold: row.active
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 110
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.tag
                            color: Skin.categoryColor(row.modelData.tag)
                            font.family: Skin.fontLabel
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.16
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: Apps.windowsFor(row.modelData.match) > 0 ? "RUNNING" : ""
                            color: Skin.dim
                            font.family: Skin.fontLabel
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.10
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
                    visible: win.listMode && win.pageItems.length === 0
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
                            font.family: Skin.fontLabel
                            font.pixelSize: 14
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Nothing installed matches that."
                            color: Skin.body
                            font.family: Skin.fontBody
                            font.pixelSize: 16
                        }
                    }
                }
            }

            // ---------------- clip / glyph modes (25d/25e)
            //
            // Two cells: the filter query where the log box sits, and the
            // result list (clip) or 8-wide glyph grid (25e). Rows truncate
            // with an ellipsis; the selection outline can sit mid-list
            // because the clip view slides a window under it, it never pages.
            Row {
                visible: win.altMode
                width: parent.width
                height: visible ? implicitHeight : 0
                spacing: 12

                // Query cell.
                Rectangle {
                    id: altQueryCell
                    width: (parent.width - 12) / 2.6
                    height: Math.max(altRight.height, 150)
                    color: Skin.cell
                    border.width: 2
                    border.color: Skin.inner

                    Column {
                        x: 18
                        y: 16
                        width: parent.width - 36
                        spacing: 10

                        Text {
                            text: "FILTER"
                            color: Skin.dim
                            font.family: Skin.fontLabel
                            font.pixelSize: 10
                            font.letterSpacing: 10 * 0.18
                        }

                        Row {
                            spacing: 2

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: win.query
                                color: Skin.text
                                font.family: Skin.fontBody
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
                    }

                    Text {
                        x: 18
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        text: win.mode === "glyphs"
                            ? win.altResults.length + " glyphs"
                            : (win.altResults.length === 0 ? 0 : win.selected + 1)
                              + " of " + win.altResults.length + " entries"
                        color: Skin.dim
                        font.family: Skin.fontBody
                        font.pixelSize: 14
                    }
                }

                // Result cell.
                Rectangle {
                    width: parent.width - 12 - altQueryCell.width
                    height: altRight.height
                    color: "transparent"

                    Item {
                        id: altRight
                        width: parent.width
                        height: childrenRect.height

                        // Clipboard rows.
                        Column {
                            visible: win.mode === "clip" && win.altItems.length > 0
                            width: parent.width
                            spacing: 6

                            Repeater {
                                model: win.mode === "clip" ? win.altItems : []

                                Rectangle {
                                    id: clipRow

                                    required property int index
                                    required property var modelData

                                    readonly property bool active:
                                        win.selected === win.altStart + index
                                    readonly property bool isImg:
                                        win.isImgPreview(modelData.preview || "")

                                    width: parent.width
                                    height: 42
                                    color: Skin.cell

                                    Text {
                                        visible: !clipRow.isImg
                                        x: 14
                                        width: parent.width - 28
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: clipRow.modelData.preview || ""
                                        color: Skin.body
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        font.family: Skin.fontBody
                                        font.pixelSize: 16
                                    }

                                    // Image entry: the picture itself, pixel
                                    // crisp, with a dim tag beside it.
                                    Image {
                                        visible: clipRow.isImg
                                        x: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 34
                                        width: Math.min(implicitWidth * 34 / Math.max(1, implicitHeight), 220)
                                        fillMode: Image.PreserveAspectFit
                                        smooth: false
                                        asynchronous: true
                                        source: clipRow.isImg && win.thumbsReady
                                            ? "file://" + win.thumbDir + "/"
                                              + clipRow.modelData.cid + ".png"
                                            : ""
                                    }

                                    Text {
                                        visible: clipRow.isImg
                                        anchors.right: parent.right
                                        anchors.rightMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "IMAGE"
                                        color: Skin.dim
                                        font.family: Skin.fontLabel
                                        font.pixelSize: 10
                                        font.letterSpacing: 10 * 0.16
                                    }

                                    Rectangle {
                                        visible: clipRow.active
                                        anchors.fill: parent
                                        color: "transparent"
                                        border.width: 2
                                        border.color: Skin.snd
                                    }

                                    TapHandler {
                                        onTapped: {
                                            win.selected = win.altStart + clipRow.index;
                                            win.altActivate();
                                        }
                                    }
                                }
                            }
                        }

                        // Glyph grid.
                        Grid {
                            visible: win.mode === "glyphs" && win.altItems.length > 0
                            width: parent.width
                            columns: 8
                            columnSpacing: 6
                            rowSpacing: 6

                            Repeater {
                                model: win.mode === "glyphs" ? win.altItems : []

                                Rectangle {
                                    id: glyphCell

                                    required property int index
                                    required property var modelData

                                    readonly property bool active: win.selected === index

                                    width: (altRight.width - 7 * 6) / 8
                                    height: 42
                                    color: Skin.cell

                                    Text {
                                        anchors.centerIn: parent
                                        // The || "" rides out the one frame
                                        // where a mode switch rebinds clip
                                        // rows into glyph cells.
                                        text: glyphCell.modelData.ch || ""
                                        color: Skin.body
                                        font.family: Skin.fontBody
                                        font.pixelSize: 20
                                    }

                                    Rectangle {
                                        visible: glyphCell.active
                                        anchors.fill: parent
                                        color: "transparent"
                                        border.width: 2
                                        border.color: Skin.snd
                                    }

                                    TapHandler {
                                        onTapped: {
                                            win.selected = glyphCell.index;
                                            win.altActivate();
                                        }
                                    }
                                }
                            }
                        }

                        // Nothing matched; the query cell stays as typed.
                        Rectangle {
                            visible: win.altMode && win.altItems.length === 0
                            width: parent.width
                            height: visible ? 150 : 0
                            color: Skin.cell

                            Column {
                                anchors.centerIn: parent
                                spacing: 10

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Skin.emptyWord
                                    color: Skin.dim
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 14
                                    font.letterSpacing: 14 * 0.18
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Nothing matches that."
                                    color: Skin.body
                                    font.family: Skin.fontBody
                                    font.pixelSize: 16
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
