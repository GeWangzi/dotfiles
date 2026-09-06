pragma Singleton

// Application data for the launcher: the four role entries an empty query
// shows, the search over installed .desktop entries, and the per-app window
// count from the compositor. Nothing here polls: window counts come from
// Hyprland's event socket and the desktop entry scan is Quickshell's own.

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    // ---------------------------------------------------------------- roles

    // What an empty query shows. Their labels are roles, not program names
    // (TERMINAL, not KITTY) on purpose. `desktopId` is only used to borrow a
    // real description; the launch command is the authority.
    readonly property var roles: [
        {
            name: "TERMINAL",
            tag: "CMD",
            fallback: "Shell session. Zsh with four saved profiles.",
            desktopId: "kitty",
            exec: ["kitty"],
            match: "kitty"
        },
        {
            name: "BROWSER",
            tag: "NET",
            fallback: "Web client.",
            desktopId: "firefox",
            exec: ["firefox"],
            match: "firefox"
        },
        {
            name: "EDITOR",
            tag: "TXT",
            fallback: "Code editor.",
            desktopId: "code",
            exec: ["code"],
            // Matches the Hyprland window class, which VS Code sets to
            // "Code" via StartupWMClass.
            match: "code"
        },
        {
            name: "MUSIC",
            tag: "SND",
            fallback: "Library player.",
            desktopId: "spotify-launcher",
            exec: ["spotify-launcher"],
            match: "spotify"
        }
    ]

    // Look an entry up by scanning the model rather than calling byId.
    //
    // This is not stubbornness: DesktopEntries populates lazily and only
    // starts scanning once something *binds* to it. byId is an imperative
    // call, so it registers no dependency -- it returned null on the first
    // evaluation, the binding was never re-run when the scan finished, and
    // every role showed its hardcoded fallback description forever.
    // Reading `applications.values` here registers the dependency, so the
    // list fills in as soon as the scan lands.
    function entryById(id) {
        const apps = DesktopEntries.applications.values;
        const want = String(id).toLowerCase();
        for (let i = 0; i < apps.length; i++) {
            const eid = String(apps[i].id || "").toLowerCase().replace(/\.desktop$/, "");
            if (eid === want) return apps[i];
        }
        return null;
    }

    function roleEntries() {
        return roles.map(function (f) {
            const entry = entryById(f.desktopId);
            return {
                name: f.name,
                tag: f.tag,
                description: (entry && entry.comment) ? entry.comment : f.fallback,
                match: f.match,
                exec: f.exec,
                entry: null
            };
        });
    }

    // ---------------------------------------------------------------- search

    // The design has four category hues and .desktop files have dozens of
    // categories, so everything funnels into those four. Order matters:
    // the first match wins, and a Development entry that is also Network
    // should read as TXT rather than NET.
    function categoryOf(entry) {
        const cats = entry.categories || [];

        function has(name) {
            return cats.indexOf(name) !== -1;
        }

        if (has("TerminalEmulator") || has("System") || has("Settings")) return "CMD";
        if (has("TextEditor") || has("Development") || has("Office")) return "TXT";
        if (has("Audio") || has("AudioVideo") || has("Video") || has("Player")) return "SND";
        if (has("Network") || has("WebBrowser")) return "NET";
        return "APP";
    }

    function processName(entry) {
        if (entry.startupClass) return entry.startupClass.toLowerCase();
        const cmd = entry.command && entry.command.length ? entry.command[0] : entry.execString;
        if (!cmd) return "";
        return String(cmd).split("/").pop().toLowerCase();
    }

    // Substring match, ranked: a name that starts with the query beats a name
    // that merely contains it, which beats a match found only in the generic
    // name, keywords or comment. Good enough for a launcher; no fuzzy matching,
    // because typos in a four-letter query are rarer than mis-ranked results.
    function search(query) {
        const q = query.toLowerCase().trim();
        if (q === "") return roleEntries();

        const scored = [];
        const apps = DesktopEntries.applications.values;

        for (let i = 0; i < apps.length; i++) {
            const entry = apps[i];
            if (entry.noDisplay) continue;

            const name = (entry.name || "").toLowerCase();
            let score = -1;

            if (name.startsWith(q)) score = 0;
            else if (name.indexOf(q) !== -1) score = 1;
            else {
                const generic = (entry.genericName || "").toLowerCase();
                const comment = (entry.comment || "").toLowerCase();
                const keywords = (entry.keywords || []).join(" ").toLowerCase();
                if (generic.indexOf(q) !== -1 || keywords.indexOf(q) !== -1) score = 2;
                else if (comment.indexOf(q) !== -1) score = 3;
            }

            if (score < 0) continue;

            scored.push({
                score: score,
                name: (entry.name || entry.id).toUpperCase(),
                tag: categoryOf(entry),
                description: entry.comment || entry.genericName || "",
                match: processName(entry),
                exec: null,
                entry: entry
            });
        }

        scored.sort(function (a, b) {
            if (a.score !== b.score) return a.score - b.score;
            return a.name.localeCompare(b.name);
        });

        return scored;
    }

    function launch(item) {
        if (item.entry) item.entry.execute();
        else Quickshell.execDetached(item.exec);
    }

    // ---------------------------------------------------------------- windows

    // Window count from the compositor. Event-driven, so this is free.
    // Reading Hyprland.toplevels.values inside the function registers the
    // dependency, so bindings on this re-run as windows open and close.
    function windowsFor(match) {
        if (!match) return 0;
        const key = match.slice(0, 15);
        const tops = Hyprland.toplevels.values;
        let n = 0;
        for (let i = 0; i < tops.length; i++) {
            const ipc = tops[i].lastIpcObject;
            const cls = (ipc && ipc.class ? String(ipc.class) : "").toLowerCase();
            if (cls !== "" && cls.startsWith(key)) n++;
        }
        return n;
    }
}
