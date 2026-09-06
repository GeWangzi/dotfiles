// Calendar + notification history. A month grid on the left, the
// notifications from the selected day and the day before it on the right. Opening it marks everything read, the same as
// the plain history list it replaces.
//
// The handoff draws the empty state as a separate 380px panel with no grid at
// all. That is not navigable -- the arrow keys would have nothing to move
// over -- so the empty treatment lives inside the history column here and the
// calendar stays put.
//
// Keyboard, extending the handoff's legend at the user's request: the grid is
// arrow-driven, and pressing Up from the top week moves onto the month header,
// where Left/Right change the month and Down drops back into the grid. Enter
// hands the arrows to the history column so a long day can be scrolled without
// the mouse. Escape backs out one zone at a time, then closes.
//
// Same overlay shape as the power menu: fullscreen transparent window,
// exclusive keyboard, Esc or an outside click dismisses.
//
// Silkscreen sizes are the design's rounded up to even (9 -> 10, 11 -> 12);
// body copy is the terminal's own face at 16, the size every other surface in
// this shell uses for the design's 13. See fonts/README.md.

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
    WlrLayershell.namespace: "shell-calendar"

    // ---------------- state
    //
    // Timestamps are local midnights in milliseconds and are held as `real`,
    // not `int`: an epoch millisecond is far past what a 32-bit int holds and
    // silently wraps if declared as one.

    property real todayTs: win.dayStart(Date.now())
    property real selectedTs: win.dayStart(Date.now())
    property int monthYear: new Date().getFullYear()
    property int monthIndex: new Date().getMonth()

    // Which zone the arrows drive: the month header, the day grid, or the
    // history column.
    property string zone: "grid"

    // The design's fourth text step (#6A5A8C against #9A83C2) has no token of
    // its own. On a dark panel a dimmer step is the dim token let down toward
    // the background, which is what this is -- not a hardcoded colour.
    readonly property color dimmest: Qt.rgba(Skin.dim.r, Skin.dim.g, Skin.dim.b, 0.68)

    readonly property var monthWords: ["JANUARY", "FEBRUARY", "MARCH", "APRIL",
        "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER",
        "DECEMBER"]
    readonly property var monthShort: ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
        "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    readonly property var dayShort: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    // ---------------- date helpers
    //
    // Everything goes through the Date constructor rather than through
    // arithmetic on milliseconds, so a day step across a DST boundary is still
    // one day.

    function dayStart(ms) {
        const d = new Date(ms);
        return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    }

    function addDays(ms, n) {
        const d = new Date(ms);
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n).getTime();
    }

    function hhmm(ms) {
        const d = new Date(ms);
        return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2);
    }

    // ISO-8601 week. Step to the Thursday the week owns -- week 1 is by
    // definition the week holding the first Thursday of the year -- and then
    // the week is just that Thursday's position in its own year.
    function isoWeek(ms) {
        const d = new Date(win.dayStart(ms));
        d.setDate(d.getDate() + 3 - ((d.getDay() + 6) % 7));
        return Math.floor((win.dayOfYear(d.getTime()) - 1) / 7) + 1;
    }

    function dayOfYear(ms) {
        const d = new Date(ms);
        return Math.round((win.dayStart(ms)
            - new Date(d.getFullYear(), 0, 1).getTime()) / 86400000) + 1;
    }

    function dateWord(ms) {
        const d = new Date(ms);
        return win.dayShort[d.getDay()] + " " + d.getDate() + " "
             + win.monthShort[d.getMonth()];
    }

    // Group titles say TODAY for the real today and the weekday otherwise.
    function groupWord(ms) {
        return ms === win.todayTs ? "TODAY" : win.dateWord(ms);
    }

    // ---------------- the grid
    //
    // Six Monday-first weeks, always 42 cells, so the frame never changes
    // height between months.

    readonly property var weeks: {
        const first = new Date(win.monthYear, win.monthIndex, 1);
        const lead = (first.getDay() + 6) % 7;
        const start = new Date(win.monthYear, win.monthIndex, 1 - lead).getTime();
        const out = [];
        for (let r = 0; r < 6; r++) {
            const row = [];
            for (let c = 0; c < 7; c++) {
                const ts = win.addDays(start, r * 7 + c);
                const d = new Date(ts);
                row.push({
                    ts: ts,
                    day: d.getDate(),
                    inMonth: d.getMonth() === win.monthIndex,
                    weekend: d.getDay() === 0 || d.getDay() === 6,
                });
            }
            out.push(row);
        }
        return out;
    }

    // Which week row carries the cursor, or -1 when the selected day is not on
    // the displayed grid at all (the month was stepped away from it).
    readonly property int selectedRow: {
        for (let r = 0; r < win.weeks.length; r++)
            for (let c = 0; c < 7; c++)
                if (win.weeks[r][c].ts === win.selectedTs)
                    return r;
        return -1;
    }

    // ---------------- the held events
    //
    // Held notifications bucketed by local day. Notifs.events is newest first,
    // so each bucket already is.

    readonly property var byDay: {
        const m = ({});
        Notifs.events.forEach(ev => {
            const k = "" + win.dayStart(ev.ts);
            if (!m[k]) m[k] = [];
            m[k].push(ev);
        });
        return m;
    }

    function eventsOn(ts) {
        return win.byDay["" + ts] || [];
    }

    // One dot per source, three at most, critical first and then in recency
    // order -- the handoff's priority rule.
    function dotsOn(ts) {
        const evs = win.eventsOn(ts);
        const seen = ({});
        const out = [];
        if (evs.some(e => e.critical)) out.push(Skin.critical);
        evs.forEach(e => {
            if (e.critical || seen[e.tag]) return;
            seen[e.tag] = true;
            out.push(Skin.categoryColor(e.tag));
        });
        return out.slice(0, 3);
    }

    // The history column's scope: the selected day and the day before it,
    // newest first, one time rule each. Empty days drop out entirely.
    readonly property var logGroups: {
        const out = [];
        [win.selectedTs, win.addDays(win.selectedTs, -1)].forEach(ts => {
            const rows = win.eventsOn(ts).map(ev => ({ ev: ev, when: win.hhmm(ev.ts) }));
            if (rows.length > 0)
                out.push({ ts: ts, title: win.groupWord(ts), rows: rows });
        });
        return out;
    }

    // ---------------- movement

    function selectDay(ts) {
        win.selectedTs = ts;
        const d = new Date(ts);
        win.monthYear = d.getFullYear();
        win.monthIndex = d.getMonth();
        win.zone = "grid";
    }

    function stepDay(n) {
        // After the month was stepped away from the selection there is no
        // cursor on the grid; the first arrow press puts it back rather than
        // yanking the view to wherever the selection still sits.
        if (win.selectedRow === -1) {
            win.enterGrid();
            return;
        }
        win.selectDay(win.addDays(win.selectedTs, n));
    }

    function stepMonth(n) {
        const d = new Date(win.monthYear, win.monthIndex + n, 1);
        win.monthYear = d.getFullYear();
        win.monthIndex = d.getMonth();
    }

    // Dropping from the month header into the grid. If the month was stepped
    // away from the selection, the selection snaps into the displayed month on
    // the same day number (clamped, so the 31st of a 30-day month lands).
    function enterGrid() {
        win.zone = "grid";
        if (win.selectedRow !== -1) return;
        const last = new Date(win.monthYear, win.monthIndex + 1, 0).getDate();
        const day = Math.min(new Date(win.selectedTs).getDate(), last);
        win.selectedTs = new Date(win.monthYear, win.monthIndex, day).getTime();
    }

    function clearShown() {
        Notifs.clearDays([win.selectedTs, win.addDays(win.selectedTs, -1)]);
    }

    onSelectedTsChanged: logScroll.contentY = 0

    onVisibleChanged: {
        if (visible) {
            Notifs.markAllRead();
            win.todayTs = win.dayStart(Date.now());
            win.selectDay(win.todayTs);
            logScroll.contentY = 0;
            keys.forceActiveFocus();
        }
    }

    // The outline has to move at midnight. One wake a minute, and only while
    // the panel is on screen.
    Timer {
        interval: 60000
        repeat: true
        running: win.visible
        onTriggered: win.todayTs = win.dayStart(Date.now())
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        TapHandler {
            onTapped: eventPoint => {
                const p = calFrame.mapFromItem(keys,
                    eventPoint.position.x, eventPoint.position.y);
                if (p.x < 0 || p.y < 0 || p.x > calFrame.width || p.y > calFrame.height)
                    win.dismissed();
            }
        }

        Keys.onPressed: event => {
            event.accepted = true;
            switch (event.key) {
            case Qt.Key_Escape:
                if (win.zone === "grid") win.dismissed();
                else win.zone = "grid";
                break;
            case Qt.Key_Left:
            case Qt.Key_H:
                if (win.zone === "month") win.stepMonth(-1);
                else if (win.zone === "grid") win.stepDay(-1);
                else win.zone = "grid";
                break;
            case Qt.Key_Right:
            case Qt.Key_L:
                if (win.zone === "month") win.stepMonth(1);
                else if (win.zone === "grid") win.stepDay(1);
                break;
            case Qt.Key_Up:
            case Qt.Key_K:
                if (win.zone === "month") break;
                if (win.zone === "log") {
                    logScroll.contentY = Math.max(0, logScroll.contentY - 64);
                    break;
                }
                // Up off the top week is how the month header is reached.
                if (win.selectedRow === 0) win.zone = "month";
                else win.stepDay(-7);
                break;
            case Qt.Key_Down:
            case Qt.Key_J:
                if (win.zone === "month") win.enterGrid();
                else if (win.zone === "grid") win.stepDay(7);
                else logScroll.contentY = Math.max(0,
                    Math.min(logScroll.contentHeight - logScroll.height,
                             logScroll.contentY + 64));
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (win.zone === "month") win.enterGrid();
                else if (win.zone === "grid" && win.logGroups.length > 0)
                    win.zone = "log";
                break;
            case Qt.Key_BracketLeft:
                win.stepMonth(-1);
                break;
            case Qt.Key_BracketRight:
                win.stepMonth(1);
                break;
            case Qt.Key_Delete:
                win.clearShown();
                break;
            case Qt.Key_Home:
                win.selectDay(win.todayTs);
                break;
            default:
                event.accepted = false;
            }
        }

        Frame {
            id: calFrame
            anchors.centerIn: parent
            width: 900
            padTop: 26
            padSide: 24
            padBottom: 18
            title: "CALENDAR"

            readonly property int inner: 900 - 2 * (calFrame.frameBorder + 24)   // 848

            Column {
                width: calFrame.inner
                spacing: 16

                // ---- header: month stepper
                Item {
                    width: parent.width
                    height: monthWord.implicitHeight

                    // The month zone's cursor, in the grid's own gutter.
                    Blink {
                        visible: win.zone === "month"
                        width: 16
                        height: parent.height
                        Text {
                            anchors.centerIn: parent
                            text: Skin.glyph
                            color: Skin.text
                            font.family: Skin.fontLabel
                            font.pixelSize: 10
                        }
                    }

                    Row {
                        x: 16
                        spacing: 14

                        Text {
                            anchors.verticalCenter: monthWord.verticalCenter
                            text: "◀"
                            color: win.zone === "month" ? Skin.text : Skin.dim
                            font.family: Skin.fontLabel
                            font.pixelSize: 10

                            TapHandler { onTapped: win.stepMonth(-1) }
                        }

                        Text {
                            id: monthWord
                            text: win.monthWords[win.monthIndex] + " " + win.monthYear
                            color: Skin.text
                            font.family: Skin.fontLabel
                            font.bold: true
                            font.pixelSize: 12
                            font.letterSpacing: 12 * Skin.trackWide

                            TapHandler { onTapped: win.zone = "month" }
                        }

                        Text {
                            anchors.verticalCenter: monthWord.verticalCenter
                            text: "▶"
                            color: win.zone === "month" ? Skin.text : Skin.dim
                            font.family: Skin.fontLabel
                            font.pixelSize: 10

                            TapHandler { onTapped: win.stepMonth(1) }
                        }
                    }
                }

                // ---- body: grid left, history right
                Row {
                    width: parent.width
                    spacing: 26

                    Column {
                        id: gridCol
                        width: 372
                        spacing: 6

                        // Weekday header. The 16px indent is the cursor gutter.
                        Row {
                            x: 16
                            spacing: 4

                            Repeater {
                                model: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

                                delegate: Text {
                                    required property var modelData
                                    required property int index

                                    width: 44
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    color: index > 4 ? Skin.dim : Skin.body
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 10
                                    font.letterSpacing: 10 * Skin.trackLabel
                                }
                            }
                        }

                        Rectangle {
                            width: gridCol.width
                            height: 2
                            color: Skin.inner
                        }

                        Repeater {
                            model: win.weeks

                            delegate: Item {
                                id: weekRow
                                required property var modelData
                                required property int index

                                width: gridCol.width
                                height: 38

                                Row {
                                    x: 16
                                    spacing: 4

                                    Repeater {
                                        model: weekRow.modelData

                                        delegate: Item {
                                            id: cell
                                            required property var modelData

                                            width: 44
                                            height: 38

                                            readonly property bool today:
                                                cell.modelData.ts === win.todayTs
                                            readonly property bool selected:
                                                cell.modelData.ts === win.selectedTs
                                            readonly property var dots:
                                                win.dotsOn(cell.modelData.ts)

                                            Rectangle {
                                                visible: cell.today
                                                anchors.fill: parent
                                                color: "transparent"
                                                border.width: 2
                                                border.color: Skin.text
                                            }

                                            // The selection is its own box on
                                            // the cell, so a left/right step
                                            // inside one week is visible. The
                                            // handoff put the cursor in a row
                                            // gutter instead, which only ever
                                            // moved up and down (user call).
                                            // Still an outline, never a fill or
                                            // an inversion, and it does not
                                            // blink -- the box is where you
                                            // are, not something asking for
                                            // attention.
                                            Rectangle {
                                                visible: cell.selected
                                                anchors.fill: parent
                                                color: "transparent"
                                                border.width: 2
                                                border.color: Skin.snd
                                            }

                                            Column {
                                                anchors.centerIn: parent
                                                spacing: 3

                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: cell.modelData.day
                                                    // Hover raises the number one
                                                    // step and does nothing else.
                                                    color: cell.today || cellHover.hovered
                                                        ? Skin.text
                                                        : !cell.modelData.inMonth ? win.dimmest
                                                        : cell.modelData.weekend ? Skin.dim
                                                        : Skin.body
                                                    font.family: Skin.fontBody
                                                    font.pixelSize: 16
                                                }

                                                Row {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    spacing: 3
                                                    visible: cell.dots.length > 0

                                                    Repeater {
                                                        model: cell.dots

                                                        delegate: Rectangle {
                                                            required property var modelData
                                                            width: 4
                                                            height: 4
                                                            color: modelData
                                                        }
                                                    }
                                                }
                                            }

                                            HoverHandler { id: cellHover }
                                            TapHandler {
                                                onTapped: win.selectDay(cell.modelData.ts)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- history for the selected day
                    Item {
                        width: calFrame.inner - gridCol.width - 26
                        height: gridCol.height

                        Rectangle {
                            id: logPanel
                            anchors.fill: parent
                            anchors.topMargin: 15
                            color: "transparent"
                            border.width: 2
                            border.color: Skin.inner

                            // The tab knocks a hole in the keyline, so it is
                            // painted in the frame's own fill.
                            Rectangle {
                                x: 14
                                y: -height / 2
                                width: logTab.implicitWidth + 16
                                height: logTab.implicitHeight + 4
                                color: Skin.window

                                Text {
                                    id: logTab
                                    anchors.centerIn: parent
                                    text: "HISTORY"
                                    color: Skin.text
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 10
                                    font.letterSpacing: 10 * Skin.trackLabel
                                }
                            }

                            // Empty day: the handoff's NO DATA treatment, kept
                            // inside the column so the grid stays navigable.
                            Column {
                                visible: win.logGroups.length === 0
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "EMPTY"
                                    color: win.dimmest
                                    font.family: Skin.fontLabel
                                    font.pixelSize: 12
                                    font.letterSpacing: 12 * Skin.trackWide
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Nothing on this day."
                                    color: win.dimmest
                                    font.family: Skin.fontBody
                                    font.pixelSize: 16
                                }
                            }

                            Flickable {
                                id: logScroll
                                visible: win.logGroups.length > 0
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: actionRow.top
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                anchors.topMargin: 22
                                anchors.bottomMargin: 12
                                contentWidth: width
                                contentHeight: logEntries.implicitHeight
                                clip: true
                                interactive: contentHeight > height

                                Column {
                                    id: logEntries
                                    width: logScroll.width
                                    spacing: 12

                                    Repeater {
                                        model: win.logGroups

                                        delegate: Column {
                                            id: group
                                            required property var modelData
                                            required property int index

                                            width: logEntries.width
                                            spacing: 10

                                            // Time rule: label, bar, count.
                                            Item {
                                                width: parent.width
                                                height: groupLabel.implicitHeight

                                                Text {
                                                    id: groupLabel
                                                    text: group.modelData.title
                                                    color: Skin.dim
                                                    font.family: Skin.fontLabel
                                                    font.pixelSize: 10
                                                    font.letterSpacing: 10 * Skin.trackLabel
                                                }

                                                Rectangle {
                                                    anchors.left: groupLabel.right
                                                    anchors.right: groupCount.left
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    height: 2
                                                    color: Skin.inner
                                                }

                                                Text {
                                                    id: groupCount
                                                    anchors.right: parent.right
                                                    text: group.modelData.rows.length + " ENTRIES"
                                                    color: win.dimmest
                                                    font.family: Skin.fontLabel
                                                    font.pixelSize: 10
                                                    font.letterSpacing: 10 * Skin.trackLabel
                                                }
                                            }

                                            Repeater {
                                                model: group.modelData.rows

                                                delegate: Rectangle {
                                                    id: entry
                                                    required property var modelData

                                                    // The day before the selected
                                                    // one is dimmed one step.
                                                    readonly property bool older: group.index > 0
                                                    readonly property bool critical:
                                                        !!entry.modelData.ev.critical
                                                    readonly property int pad: entry.critical ? 12 : 0

                                                    readonly property string primary:
                                                        entry.modelData.ev.headline
                                                        || entry.modelData.ev.body || ""
                                                    readonly property string secondary:
                                                        entry.modelData.ev.headline
                                                            ? (entry.modelData.ev.body
                                                               || entry.modelData.ev.subline || "")
                                                            : (entry.modelData.ev.subline || "")

                                                    width: logEntries.width
                                                    height: Math.max(entryBody.implicitHeight
                                                        + entrySub.height, 20) + 2 * (entry.critical ? 10 : 0)
                                                    color: "transparent"
                                                    border.width: entry.critical ? 2 : 0
                                                    border.color: Skin.critical

                                                    Text {
                                                        id: entryTime
                                                        x: entry.pad
                                                        anchors.baseline: entryBody.baseline
                                                        width: 42
                                                        text: entry.modelData.when
                                                        color: entry.critical ? Skin.critical : win.dimmest
                                                        font.family: Skin.fontLabel
                                                        font.pixelSize: 10
                                                    }

                                                    Chip {
                                                        id: entryChip
                                                        x: entryTime.x + 52
                                                        y: entry.pad > 0 ? 10 : 0
                                                        label: entry.critical ? "SYS" : entry.modelData.ev.tag
                                                        hue: entry.critical
                                                            ? Skin.critical
                                                            : Skin.categoryColor(entry.modelData.ev.tag)
                                                    }

                                                    Text {
                                                        id: entryBody
                                                        anchors.left: entryChip.right
                                                        anchors.leftMargin: 10
                                                        anchors.right: parent.right
                                                        anchors.rightMargin: entry.pad
                                                        y: entry.pad > 0 ? 10 : 0
                                                        text: entry.primary
                                                        color: entry.critical ? Skin.text
                                                             : entry.older ? Skin.dim : Skin.body
                                                        wrapMode: Text.Wrap
                                                        lineHeight: 1.35
                                                        font.family: Skin.fontBody
                                                        font.pixelSize: 16
                                                    }

                                                    // The outcome or detail line.
                                                    Text {
                                                        id: entrySub
                                                        anchors.left: entryBody.left
                                                        anchors.right: entryBody.right
                                                        anchors.top: entryBody.bottom
                                                        visible: entry.secondary !== ""
                                                        height: visible ? implicitHeight : 0
                                                        text: entry.secondary
                                                        color: entry.modelData.ev.resultColor
                                                            ? entry.modelData.ev.resultColor
                                                            : entry.older ? win.dimmest : Skin.dim
                                                        wrapMode: Text.Wrap
                                                        lineHeight: 1.35
                                                        font.family: Skin.fontBody
                                                        font.pixelSize: 16
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ---- CLEAR ALL, for the days on show
                            Row {
                                id: actionRow
                                visible: win.logGroups.length > 0
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 20
                                anchors.bottomMargin: 18
                                spacing: 12

                                Rectangle {
                                    width: clearWord.implicitWidth + 18
                                    height: clearWord.implicitHeight + 6
                                    color: "transparent"
                                    border.width: 2
                                    border.color: win.zone === "log" ? Skin.snd : Skin.inner

                                    Text {
                                        id: clearWord
                                        anchors.centerIn: parent
                                        text: "CLEAR ALL"
                                        color: win.zone === "log" ? Skin.text : Skin.body
                                        font.family: Skin.fontLabel
                                        font.pixelSize: 10
                                        font.letterSpacing: 10 * Skin.trackLabel
                                    }

                                    TapHandler { onTapped: win.clearShown() }
                                }
                            }
                        }
                    }
                }

                // ---- key legend, which follows the zone the arrows drive
                Row {
                    spacing: 18

                    Repeater {
                        model: win.zone === "month"
                            ? ["←→ MONTH", "↓ GRID", "↵ GRID", "ESC BACK"]
                            : win.zone === "log"
                            ? ["↑↓ SCROLL", "DEL CLEAR", "ESC BACK"]
                            : ["←→ DAY", "↑↓ WEEK", "↑ MONTH", "[ ] MONTH",
                               "↵ LOG", "ESC CLOSE"]

                        delegate: Text {
                            required property var modelData
                            text: modelData
                            color: win.dimmest
                            font.family: Skin.fontLabel
                            font.pixelSize: 10
                            font.letterSpacing: 10 * Skin.trackLabel
                        }
                    }
                }
            }
        }
    }
}
