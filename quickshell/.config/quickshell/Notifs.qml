pragma Singleton

// The notification daemon. This singleton IS the org.freedesktop.Notifications
// owner -- instantiating NotificationServer claims the bus name, so swaync
// must not be running alongside it.
//
// Events are plain JS objects, newest first:
//
//   { id, tag, headline, body, critical, ts, read, timeout }
//
// `presented` is the subset currently toasting (Toasts.qml renders it).
// While `dnd` is up nothing presents; events accumulate silently in history
// and surface unread on the calendar page.
//
// Copy rule: the body line is always the application's own text, verbatim,
// never invented.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root

    property var events: []
    property var presented: []
    property bool dnd: false
    property int unreadCount: 0

    property int nextId: 1

    // Live server-notification refs by event id, kept out of `events` so the
    // event list stays plain data (dismiss/action invocation only).
    property var nrefs: ({})

    function toggleDnd() {
        dnd = !dnd;
        if (dnd) presented = [];
    }

    // App name -> tag chip. The tag picks the chip hue via
    // Skin.categoryColor and the headline shape below.
    function tagFor(appName) {
        const n = (appName || "").toLowerCase();
        if (/firefox|chrom|zen|browser|discord|thunderbird|mail|network|nm-|wifi|blueman|transmission|qbittorrent/.test(n))
            return "NET";
        if (/spotify|mpv|vlc|mpd|audio|pipewire|wireplumber/.test(n))
            return "SND";
        if (/nvim|vim|code|editor|obsidian|libreoffice|zathura/.test(n))
            return "TXT";
        return "CMD";
    }

    // The headline is the app's own summary where one exists; NET and SND
    // notifications lead with the app name instead, because a browser's or
    // player's summary is usually a page or track title that reads better
    // as the body. Headlines are composed at ingest and persisted.
    function compose(tag, appName, summary, body) {
        const app = (appName || "APP").toUpperCase();
        if (tag === "NET" || tag === "SND")
            return { headline: app,
                     body: [summary, body].filter(Boolean).join(" — ") };
        if (summary)
            return { headline: summary.toUpperCase(), body: body || "" };
        return { headline: "NOTIFICATION", body: body || "" };
    }

    function ingest(n) {
        n.tracked = true;
        const tag = tagFor(n.appName);
        const text = compose(tag, n.appName, n.summary, n.body);
        const ev = {
            id: nextId++,
            tag: tag,
            headline: text.headline,
            body: text.body,
            critical: n.urgency === NotificationUrgency.Critical,
            ts: Date.now(),
            read: false,
            timeout: n.expireTimeout > 0 ? n.expireTimeout : 6000,
        };
        nrefs[ev.id] = n;
        add(ev);
    }

    function add(ev) {
        events = [ev].concat(events).slice(0, 200);
        unreadCount++;
        if (!dnd) presented = [ev].concat(presented);
    }

    // A toast was clicked or timed out. Read + gone from the stack; the
    // event stays in history.
    function acknowledge(id) {
        presented = presented.filter(e => e.id !== id);
        const ev = events.find(e => e.id === id);
        if (ev && !ev.read) {
            ev.read = true;
            unreadCount = Math.max(0, unreadCount - 1);
            events = events.slice();
        }
        const n = nrefs[id];
        if (n) {
            delete nrefs[id];
            try { n.dismiss(); } catch (e) { /* already closed by the app */ }
        }
    }

    function dismissAll() {
        const shown = presented;
        presented = [];
        shown.forEach(e => acknowledge(e.id));
    }

    // The calendar page's CLEAR ALL: drop every held event that falls on one
    // of the given local midnights. Anything still toasting goes with it, and
    // the live notification is dismissed so the app is told.
    function clearDays(dayStarts) {
        const wanted = ({});
        dayStarts.forEach(t => wanted["" + t] = true);
        const doomed = events.filter(e => wanted["" + dayOf(e.ts)]);
        doomed.forEach(e => {
            presented = presented.filter(p => p.id !== e.id);
            const n = nrefs[e.id];
            if (n) {
                delete nrefs[e.id];
                try { n.dismiss(); } catch (err) { /* already closed */ }
            }
        });
        events = events.filter(e => !wanted["" + dayOf(e.ts)]);
        unreadCount = events.filter(e => !e.read).length;
    }

    function dayOf(ms) {
        const d = new Date(ms);
        return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    }

    function markAllRead() {
        events.forEach(e => e.read = true);
        events = events.slice();
        unreadCount = 0;
    }

    // ---------------- persistence
    //
    // SUPER+SHIFT+R restarts the whole shell, and the BATTLE LOG's EARLIER
    // group implies days of retention, so history outlives the process.
    // Debounced writes; live notification refs and toast actions are
    // process-local and simply fall out of the JSON.

    readonly property string storeDir:
        (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
        + "/quickshell"

    property bool restored: false

    FileView {
        id: store
        path: root.storeDir + "/notif-history.json"
        printErrors: false

        onLoaded: {
            if (root.restored) return;
            root.restored = true;
            try {
                const old = JSON.parse(text()).filter(e => e && e.id && e.ts);
                old.forEach(e => e.read = true);
                root.events = root.events.concat(old).slice(0, 200);
                root.nextId = old.reduce((m, e) => Math.max(m, e.id), root.nextId) + 1;
            } catch (e) { /* fresh or corrupt store; start empty */ }
        }
    }

    onEventsChanged: saveTimer.restart()

    Timer {
        id: saveTimer
        interval: 2000
        onTriggered: store.setText(JSON.stringify(root.events))
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", storeDir]);
    }

    NotificationServer {
        keepOnReload: true
        bodySupported: true
        actionsSupported: true
        persistenceSupported: true
        imageSupported: false
        bodyMarkupSupported: false

        onNotification: n => root.ingest(n)
    }
}
