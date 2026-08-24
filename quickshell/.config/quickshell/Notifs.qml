pragma Singleton

// The notification daemon, from turns 25a-25c of the connect/notifications
// handoff. This singleton IS the org.freedesktop.Notifications owner --
// instantiating NotificationServer claims the bus name, so swaync must not be
// running alongside it.
//
// Events are plain JS objects, newest first:
//
//   { id, tag, headline, body, critical, ts, read, timeout,
//     target?, resultChip?, resultColor?, subline?, actions? }
//
// `presented` is the subset currently toasting (Toasts.qml renders it).
// While `dnd` is up (the SUB field effect, 25b) nothing presents; events
// accumulate silently in history and surface unread in the BATTLE LOG.
//
// Copy rules (non-negotiable, from the handoff): the headline may flavour the
// event with the machine as actor, but the body line is always the
// application's own text, verbatim, never invented.
//
// push() is the 25k API: the CONNECT surface delivers its outcome cards
// through the same pipeline -- they are ordinary events with a result chip,
// not a separate widget.

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
    // Skin.categoryColor and the headline flavour below.
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

    // The headline is the app's own summary where one exists; the tagged
    // fallbacks are plain (the app name) unless the creature voice puts the
    // machine in the actor role through the notif_* lexicon keys. The body
    // is never flavoured. Headlines are composed at ingest and persisted, so
    // history keeps the voice it was written in across skin switches.
    function compose(tag, appName, summary, body) {
        const app = (appName || "APP").toUpperCase();
        const subs = { name: Skin.species, app: app };
        if (tag === "NET")
            return { headline: Skin.phrase("notif_net", "{app}", subs),
                     body: [summary, body].filter(Boolean).join(" — ") };
        if (tag === "SND")
            return { headline: Skin.phrase("notif_snd", "{app}", subs),
                     body: [summary, body].filter(Boolean).join(" — ") };
        if (summary)
            return { headline: summary.toUpperCase(), body: body || "" };
        return { headline: Skin.phrase("notif_plain", "NOTIFICATION", subs),
                 body: body || "" };
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

    // The 25k entry point. o: { tag, target, critical?, chip, chipColor,
    // line, subline?, actions? } -- actions are [{ label, act() }].
    function push(o) {
        add({
            id: nextId++,
            tag: o.tag || "NET",
            target: o.target || "",
            headline: "",
            body: o.line || "",
            critical: !!o.critical,
            ts: Date.now(),
            read: false,
            timeout: o.actions ? 0 : 8000,
            resultChip: o.chip || "",
            resultColor: "" + (o.chipColor || Skin.accent),
            subline: o.subline || "",
            actions: o.actions || null,
        });
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
