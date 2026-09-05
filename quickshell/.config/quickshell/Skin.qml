pragma Singleton

// The active skin, read from the file skinctl generates.
//
// This is the QML end of the pipeline that starts in ~/.config/skins/skins.toml:
// skinctl renders that into ~/.local/state/skins/skin.json among other formats,
// and everything here reads from it. Nothing in this directory should ever
// contain a hex colour except the fallbacks below.
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

    readonly property string skinName: data.name ? data.name : "EMBER"

    // The sixteen design tokens. Fallbacks are Ember, so a missing skin.json
    // degrades to the machine's own palette rather than to black on black.
    readonly property color bg:      token("bg",      "#262126")
    readonly property color shadow:  token("shadow",  "#0b090a")
    readonly property color window:  token("window",  "#322c31")
    readonly property color outer:   token("outer",   "#f96b69")
    readonly property color inner:   token("inner",   "#482b2c")
    readonly property color cell:    token("cell",    "#1e1a1e")
    readonly property color strip:   token("strip",   "#161215")
    readonly property color text:    token("text",    "#ede0dc")
    readonly property color body:    token("body",    "#c9b6b3")
    readonly property color dim:     token("dim",     "#8a7a7c")
    readonly property color accent:  token("accent",  "#e8a04a")
    readonly property color outline: token("outline", "#f96b69")

    readonly property color cmd: token("cmd", "#e8a04a")
    readonly property color net: token("net", "#c9b6b3")
    readonly property color txt: token("txt", "#ded0c4")
    readonly property color snd: token("snd", "#f96b69")

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

    // Status-condition chip hues, also skin-independent (creature handoff):
    // SLP is suspend, BRN is thermal throttling, PAR is latency/packet loss.
    readonly property color slp: threshold("slp", "#7cb8ff")
    readonly property color brn: threshold("brn", "#ff7a3c")
    readonly property color par: threshold("par", "#ffd36b")

    // HP colour by remaining fraction: ok above 50%, warn to 20%, critical
    // below. Used by every HP bar in the shell.
    function hpColor(fraction) {
        return fraction > 0.5 ? ok : fraction > 0.2 ? warn : critical;
    }

    // The creature block, when the active skin is a creature. Fallbacks make
    // a non-creature skin read as a plain machine rather than crashing the
    // bar: the species falls back to the skin name, the types to nothing.
    readonly property var creature: data.creature || null

    function cr(name, fallback) {
        return (data.creature && data.creature[name] !== undefined)
            ? data.creature[name] : fallback;
    }

    readonly property string species:  cr("species", skinName)
    readonly property int level:       cr("level", 1)
    readonly property string type1:    cr("type1", "")
    readonly property string type2:    cr("type2", "")
    readonly property color type1Hue:  cr("type1_hue", "#9a83c2")
    readonly property color type2Hue:  cr("type2_hue", "#9a83c2")
    readonly property string ability:  cr("ability", "")
    readonly property string nature:   cr("nature", "")
    readonly property string ballWord: cr("ball", "POKE BALL")
    readonly property string crNote:   cr("note", "")
    readonly property string heldCharge:  cr("held_charge", "LEFTOVERS")
    readonly property string heldBattery: cr("held_battery", "GANLON BERRY")

    // The features block: which shell elements render at all. skinctl merges
    // the global [features] table (the plain shell's answer -- creature
    // furniture off), the skin's voice, and the skin's own table before this
    // file ever sees it. An absent key means ON, which is what real content
    // (the menu sections) relies on. Gate an element with Skin.has("...") --
    // the set of gates in the QML is the canonical key list.
    readonly property var features: data.features || null

    function has(name) {
        return (data.features && data.features[name] !== undefined)
            ? data.features[name] : true;
    }

    // The variants block: which implementation fills a slot. A slot site
    // switches on the returned name and MUST default to its plain
    // implementation for any name it does not know, so an unknown pick
    // degrades rather than blanks the surface. Slots today: lock ("plain" /
    // "card"), idle ("plain" / "moves"), field ("plain" / "creature"),
    // summary ("plain" / "creature"), menu ("deck" / "game"),
    // meter ("flat" / "blocks").
    readonly property var variants: data.variants || null

    function variant(slot, fallback) {
        return (data.variants && data.variants[slot] !== undefined)
            ? data.variants[slot] : fallback;
    }

    // The lexicon block: per-skin overrides for the shell's wording. Every
    // fallback passed to lex()/phrase() at a call site is the PLAIN wording
    // -- the shell's native voice -- and the creature voice restores the
    // battle vocabulary. phrase() additionally fills {name}-style
    // placeholders, so a voice can reorder a sentence, not just reword it.
    readonly property var lexicon: data.lexicon || null

    function lex(name, fallback) {
        return (data.lexicon && data.lexicon[name] !== undefined)
            ? data.lexicon[name] : fallback;
    }

    function phrase(name, fallback, subs) {
        let out = lex(name, fallback);
        for (const key in subs)
            out = out.replace("{" + key + "}", subs[key]);
        return out;
    }

    // Behaviour tokens.
    readonly property string glyph:     behavior("glyph", "▶")

    // The advance marker ("press to continue") is its own word, not the
    // cursor pointed sideways -- a skin may star its cursors and keep ▼.
    readonly property string glyphMore: behavior("glyph_more", "▼")
    readonly property string menuWord:  behavior("menu_word", "LAUNCH")
    readonly property string emptyWord: behavior("empty_word", "EMPTY")
    readonly property int radius:       parseInt(behavior("radius", "0px")) || 0

    // Which screen edge the bar sits on. Dream Land puts it at the bottom,
    // where the HUD lives in the games; everything else keeps the top.
    readonly property string barEdge:   behavior("bar", "top")

    // The faces. Defaults are the pixel label face and the terminal's own
    // body face; a skin that names its own is also free of Silkscreen's
    // even-sizes-only bitmap rule, which belongs to that font and not to
    // the shell.
    readonly property string fontLabel: behavior("font_label", "Silkscreen")
    readonly property string fontBody:  behavior("font_body", "DejaVu Sans Mono")

    // "1s" / "0.7s" -> milliseconds. Only Dream Land is not 1s.
    readonly property int blinkMs: {
        const raw = behavior("blink", "1s");
        const seconds = parseFloat(raw);
        return isNaN(seconds) ? 1000 : Math.round(seconds * 1000);
    }

    // Dream Land is the only skin that asks for a highlight along the top edge
    // of a filled meter block. The design expresses it as an inset box-shadow,
    // which QML has no equivalent for; Meter.qml draws it as a 2px overlay
    // instead, so all that is needed here is whether to draw one at all.
    readonly property bool shine: behavior("shine", "none") !== "none"
}
