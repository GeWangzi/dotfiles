pragma Singleton

// Application data for the launcher: the favourites list, the search over
// installed .desktop entries, and the live per-app figures the detail strip
// shows.
//
// Everything expensive here is gated on `polling`, which the launcher sets
// true only while it is on screen. The memory figures come from one `ps`
// invocation every couple of seconds while the launcher is open and from
// nothing at all the rest of the time; window counts come from Hyprland's
// event socket and cost nothing either way.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    // The launcher sets this while it is visible.
    property bool polling: false

    // ---------------------------------------------------------------- favourites

    // The four apps from turn 6a of the design. Their labels are the design's
    // generic ones (TERMINAL, not KITTY) on purpose -- these are roles, not
    // program names. `desktopId` is only used to borrow a real description;
    // the launch command is the authority.
    readonly property var favourites: [
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
            // Matches both the process name and the Hyprland window class,
            // which VS Code sets to "Code" via StartupWMClass.
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
    // every favourite showed its hardcoded fallback description forever.
    // Reading `applications.values` here registers the dependency, so the
    // strip fills in as soon as the scan lands.
    function entryById(id) {
        const apps = DesktopEntries.applications.values;
        const want = String(id).toLowerCase();
        for (let i = 0; i < apps.length; i++) {
            const eid = String(apps[i].id || "").toLowerCase().replace(/\.desktop$/, "");
            if (eid === want) return apps[i];
        }
        return null;
    }

    function favouriteEntries() {
        return favourites.map(function (f) {
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
        if (q === "") return favouriteEntries();

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

    // ---------------------------------------------------------------- live figures

    // Resident set size (kilobytes) and CPU (percent) per process name,
    // summed across every process sharing a name -- which is what makes the
    // browser figure mean anything, since it is thirty processes.
    property var memByName: ({})
    property var cpuByName: ({})

    // Total RAM, so the ten blocks measure something absolute rather than
    // being scaled against whichever app happens to be largest.
    property int totalMemKb: 16 * 1024 * 1024

    FileView {
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            const line = text().split("\n").find(function (l) {
                return l.startsWith("MemTotal:");
            });
            if (line) root.totalMemKb = parseInt(line.replace(/\D+/g, ""), 10);
        }
    }

    Process {
        id: ps
        command: ["ps", "-eo", "comm=,pcpu=,rss="]
        stdout: StdioCollector {
            onStreamFinished: {
                const mem = {};
                const cpu = {};
                const lines = text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const parts = lines[i].trim().split(/\s+/);
                    if (parts.length < 3) continue;
                    const rss = parseInt(parts[parts.length - 1], 10);
                    const pct = parseFloat(parts[parts.length - 2]);
                    const name = parts.slice(0, parts.length - 2).join(" ").toLowerCase();
                    if (isNaN(rss)) continue;
                    mem[name] = (mem[name] || 0) + rss;
                    cpu[name] = (cpu[name] || 0) + (isNaN(pct) ? 0 : pct);
                }
                root.memByName = mem;
                root.cpuByName = cpu;
            }
        }
    }

    Timer {
        // Only while the launcher is on screen. A launcher that sampled the
        // process table every two seconds all day would be exactly the kind of
        // idle wakeup this whole shell is built to avoid.
        running: root.polling
        interval: 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!ps.running) ps.running = true
    }

    // `comm` is truncated to 15 characters by the kernel, so a name longer than
    // that has to be matched against the truncation. The reverse direction is
    // deliberately restricted to exactly-15-character names: without that
    // guard, matching "code" would also pick up any process called "cod" or
    // "c", which is how a launcher ends up reporting nonsense memory figures.
    function nameMatches(comm, key) {
        if (comm.startsWith(key)) return true;
        return comm.length === 15 && key.startsWith(comm);
    }

    function memKbFor(match) {
        if (!match) return 0;
        const key = match.slice(0, 15);
        const names = Object.keys(root.memByName);
        let total = 0;
        for (let i = 0; i < names.length; i++) {
            if (nameMatches(names[i], key)) total += root.memByName[names[i]];
        }
        return total;
    }

    function memBlocksFor(match) {
        const kb = memKbFor(match);
        if (kb <= 0) return 0;
        return Math.max(1, Math.min(10, Math.round(kb / root.totalMemKb * 10)));
    }

    function memLabelFor(match) {
        const kb = memKbFor(match);
        if (kb <= 0) return "";
        return (kb / 1024 / 1024).toFixed(1) + "G";
    }

    // What is actually running, as moves: one entry per window class on the
    // compositor, most windows first. The favourites keep their role names
    // (kitty reads as TERMINAL); anything else gets its desktop entry's name
    // and category, or its bare class. Reading Hyprland.toplevels.values
    // inside the function registers the dependency, so bindings on this
    // re-run as windows open and close.
    function runningApps() {
        const counts = {};
        const order = [];
        const tops = Hyprland.toplevels.values;
        for (let i = 0; i < tops.length; i++) {
            const ipc = tops[i].lastIpcObject;
            const cls = (ipc && ipc.class ? String(ipc.class) : "").toLowerCase();
            if (cls === "") continue;
            if (counts[cls] === undefined) {
                counts[cls] = 0;
                order.push(cls);
            }
            counts[cls]++;
        }
        order.sort((a, b) => counts[b] - counts[a]);

        return order.map(cls => {
            for (let i = 0; i < favourites.length; i++) {
                if (cls.startsWith(favourites[i].match))
                    return { name: favourites[i].name, tag: favourites[i].tag,
                             match: favourites[i].match };
            }
            const entry = entryById(cls);
            return {
                name: (entry && entry.name ? entry.name : cls).toUpperCase(),
                tag: entry ? categoryOf(entry) : "APP",
                match: cls
            };
        });
    }

    // PP for a move: how hard the move is being used RIGHT NOW. 20 PP when
    // the app idles, draining with its CPU use -- flat out on one core costs
    // all 20. Two earlier RAM-based mappings both read as fake (whole-GB
    // granularity pinned everything at full; share-of-RAM barely moved), and
    // "using the move spends PP" is the one reading that matches the games:
    // it drains while the app works and refills when it rests.
    function ppForCpu(pct) {
        const max = 20;
        const spent = Math.round(Math.min(1, pct / 100) * max);
        return "PP " + (max - spent) + "/" + max;
    }

    function cpuPctFor(match) {
        if (!match) return 0;
        const key = match.slice(0, 15);
        const names = Object.keys(root.cpuByName);
        let total = 0;
        for (let i = 0; i < names.length; i++) {
            if (nameMatches(names[i], key)) total += root.cpuByName[names[i]];
        }
        return Math.min(100, total);
    }

    function ppFor(match) {
        return ppForCpu(cpuPctFor(match));
    }

    // Window count from the compositor. Event-driven, so this is free.
    function windowsFor(match) {
        if (!match) return 0;
        const key = match.slice(0, 15);
        const tops = Hyprland.toplevels.values;
        let n = 0;
        for (let i = 0; i < tops.length; i++) {
            const ipc = tops[i].lastIpcObject;
            // Window classes are not truncated, so this is a plain prefix test.
            const cls = (ipc && ipc.class ? String(ipc.class) : "").toLowerCase();
            if (cls !== "" && cls.startsWith(key)) n++;
        }
        return n;
    }

    function statusFor(match) {
        const windows = windowsFor(match);
        if (windows > 0) return "RUNNING · " + windows + (windows === 1 ? " WINDOW" : " WINDOWS");
        return memKbFor(match) > 0 ? "RUNNING" : "NOT RUNNING";
    }
}
