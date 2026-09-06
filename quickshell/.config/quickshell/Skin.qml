pragma Singleton

// The active skin, read from the file skinctl generates.
//
// This is the QML end of the pipeline that starts in ~/.config/skins/skins.toml:
// skinctl renders that into ~/.local/state/skins/skin.json among other formats,
// and everything here reads from it. Nothing in this directory should ever
// contain a hex colour except the fallbacks below.
//
// Colour purpose (the rule every surface follows; skins.toml has the same
// table):
//   focus / selection            snd
//   caret, filled meter, ON      accent
//   border, divider, empty track inner
//   surface fill                 bg; rows and panels cell; the bar shadow
//   ink on a filled chip         bg
//   muted label                  dim
//   error, mute, low, danger     critical
//
// watchChanges means `skinctl set <skin>` reskins a running shell without a
// restart, the same way it already signals kitty and Hyprland.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string statePath: {
        const state = Quickshell.env("XDG_STATE_HOME")
            || (Quickshell.env("HOME") + "/.local/state");
        return state + "/skins/skin.json";
    }

    // Parsed skin.json. Empty until the first load succeeds, which is why
    // every accessor below takes a fallback.
    property var data: ({})

    function reparse() {
        try {
            root.data = JSON.parse(view.text());
        } catch (e) {
            // A malformed or half-written file must not take the shell down.
            // skinctl writes atomically so this should not happen, but the
            // fallbacks exist precisely so that it does not matter if it does.
            console.warn("Skin: could not parse " + root.statePath + ": " + e);
        }
    }

    FileView {
        id: view
        path: root.statePath
        watchChanges: true
        printErrors: false
        onLoaded: root.reparse()
        onFileChanged: {
            reload();
            root.reparse();
        }
    }

    function token(name, fallback) {
        return (data.tokens && data.tokens[name]) ? data.tokens[name] : fallback;
    }

    function threshold(name, fallback) {
        return (data.thresholds && data.thresholds[name]) ? data.thresholds[name] : fallback;
    }

    function behavior(name, fallback) {
        return (data.behavior && data.behavior[name] !== undefined)
            ? data.behavior[name] : fallback;
    }

    readonly property string skinName: data.name ? data.name : "DREAM LAND"

    // The fifteen design tokens. Fallbacks are DREAM LAND, so a missing
    // skin.json degrades to the machine's own palette rather than to black
    // on black.
    readonly property color bg:      token("bg",      "#0d0a26")
    readonly property color shadow:  token("shadow",  "#05030f")
    readonly property color window:  token("window",  "#241a5c")
    readonly property color outer:   token("outer",   "#ff5fa2")
    readonly property color inner:   token("inner",   "#2a2170")
    readonly property color cell:    token("cell",    "#17123f")
    readonly property color strip:   token("strip",   "#17123f")
    readonly property color text:    token("text",    "#f4eaff")
    readonly property color body:    token("body",    "#cbb6f0")
    readonly property color dim:     token("dim",     "#8a76c4")
    readonly property color accent:  token("accent",  "#ffcf7a")

    readonly property color cmd: token("cmd", "#7de3c8")
    readonly property color net: token("net", "#6aa8ff")
    readonly property color txt: token("txt", "#ffb26b")
    readonly property color snd: token("snd", "#ff86d0")

    function categoryColor(tag) {
        switch (tag) {
        case "CMD": return cmd;
        case "NET": return net;
        case "TXT": return txt;
        case "SND": return snd;
        }
        return text;
    }

    // Skin-independent by design: a warning that changes colour with the theme
    // is not a warning.
    readonly property color ok:       threshold("ok",       "#3ddc84")
    readonly property color warn:     threshold("warn",     "#ffc53d")
    readonly property color critical: threshold("critical", "#ff4a1f")

    // Level colour by remaining fraction: ok above 50%, warn to 20%,
    // critical below. Used by the battery meters.
    function levelColor(fraction) {
        return fraction > 0.5 ? ok : fraction > 0.2 ? warn : critical;
    }

    // Behaviour tokens.
    readonly property string glyph:     behavior("glyph", ">")
    readonly property int radius:       parseInt(behavior("radius", "0px")) || 0

    // Which screen edge the bar sits on.
    readonly property string barEdge:   behavior("bar", "top")

    // The faces: one label face, one body face. Both IBM Plex Mono today.
    readonly property string fontLabel: behavior("font_label", "IBM Plex Mono")
    readonly property string fontBody:  behavior("font_body", "IBM Plex Mono")

    // Letter spacing, as a fraction of the size: labels (10px) are tracked
    // wide, anything 12px and up only a little. Every letterSpacing in the
    // shell is one of these two.
    readonly property real trackLabel: 0.14
    readonly property real trackWide:  0.08

    // "1s" / "0.7s" -> milliseconds.
    readonly property int blinkMs: {
        const raw = behavior("blink", "1s");
        const seconds = parseFloat(raw);
        return isNaN(seconds) ? 1000 : Math.round(seconds * 1000);
    }
}
