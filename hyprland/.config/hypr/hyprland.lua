-- Hyprland config, migrated from hyprland.conf (hyprlang) to Lua for 0.55+.
-- Wiki: https://wiki.hypr.land/Configuring/Start/
--
-- RECOVERY: if Hyprland ever fails to start, drop to a TTY (Ctrl+Alt+F2) and run:
--     ~/.config/hypr/restore-lua.sh
-- That restores hyprland.lua.original (pristine, read-only). Renaming or deleting
-- hyprland.lua also works -- Hyprland then falls back to hyprland.conf.
--
-- DO NOT set the AQ DRM device-override env var here. Doing so hung Hyprland's
-- init on 2026-08-08 (watchdog SIGABRT in initServer). Aquamarine already
-- enumerates both GPUs and selects card1/amdgpu on its own, so the override is
-- unnecessary. Env vars also cannot be validated by `hyprctl reload` -- they
-- only take effect at compositor startup, i.e. a real login.

------------------
---- MONITORS ----
------------------

-- Internal panel at 60Hz: the iGPU sat at 40-50% busy just compositing at 144Hz.
-- Set mode = "1920x1080@144" to revert.
-- Panel is 1920x1080 across 310mm = 157 DPI, but toolkits assume 96 DPI, so at
-- scale 1 everything rendered at 61% of intended size. 1.5 divides cleanly
-- (1920/1.5 = 1280, 1080/1.5 = 720, both integers -- Hyprland rejects scales
-- that produce a fractional logical resolution). 1.6 is closer to the true
-- 96/157 correction if 1.5 still reads small. Set back to 1 to revert.
hl.monitor({
    output   = "eDP-1",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = 1.5,
})

-- Catch-all for external displays. was: monitor=,preferred,auto,1
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})


---------------------
---- MY PROGRAMS ----
---------------------

-- hyprlang's $vars are just Lua locals now.
local terminal    = "kitty"
local fileManager = "nautilus"
local menu        = "wofi --show drun"


-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("waybar & swaync & hypridle & hyprpaper")

    -- Polkit auth agent. Without it, GUI apps that need root (partition tools,
    -- some NetworkManager edits) get no password prompt and silently fail.
    -- The package enables itself into graphical-session.target.wants, but that
    -- target never activates under this launcher, so start the unit directly.
    hl.exec_cmd("systemctl --user start hyprpolkitagent.service")

    -- Blue-light filter. Same graphical-session.target problem as the polkit
    -- agent, so start the unit directly. Schedule lives in hyprsunset.conf.
    hl.exec_cmd("systemctl --user start hyprsunset.service")

    hl.exec_cmd("wl-paste --type text --watch cliphist store")   -- text only
    hl.exec_cmd("wl-paste --type image --watch cliphist store")  -- images only

    -- Keep the selection alive after the source window closes. Without this,
    -- Wayland drops the clipboard when the owning client exits and a plain
    -- Ctrl+V pastes nothing. "regular" only -- covering primary as well is
    -- known to fight cliphist over the middle-click selection.
    hl.exec_cmd("wl-clip-persist --clipboard regular")

    -- was: exec-once = [workspace 1 silent] firefox
    -- Dispatcher prefixes are now the rules table on exec_cmd.
    hl.dispatch(hl.dsp.exec_cmd("firefox", { workspace = "1 silent" }))
    hl.dispatch(hl.dsp.exec_cmd(terminal,  { workspace = "2 silent" }))
end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- 24 is the standard base size. These were at 32 to hand-compensate for the
-- 157 DPI panel; the monitor scale of 1.5 now does that, and 32 would render
-- as an effective 48.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Electron apps (Discord, VS Code) default to Xwayland, where the compositor
-- can only bitmap-upscale them: right size, but soft at scale 1.5. This makes
-- them native Wayland so they render sharp. "auto" falls back to X11 when
-- there is no Wayland display, so it is safe outside Hyprland too.
-- /usr/bin/discord reads no flags file, unlike /usr/bin/code -- hence the env
-- var rather than ~/.config/*-flags.conf. Needs Electron 28+; Discord 1.0.153
-- ships Chrome/148, well past that.
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
-- $HOME isn't expanded for you anymore; this is plain Lua.
hl.env("HYPRSHOT_DIR", os.getenv("HOME") .. "/Pictures/clipboard")


-----------------------
----- PERMISSIONS -----
-----------------------

-- hl.config({
--     ecosystem = {
--         enforce_permissions = true,
--     },
-- })

-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")


-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 0,

        border_size = 2,

        -- col.active_border is now a nested table; gradients are
        -- { colors = {...}, angle = deg }
        col = {
            active_border   = { colors = { "rgba(a6adc8e0)", "rgba(89b4fae0)" }, angle = 45 },
            inactive_border = "rgba(181825ff)",
        },

        resize_on_border = false,
        allow_tearing    = false,

        layout = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = "rgba(1a1a1aee)",
        },

        blur = {
            enabled  = false,
            size     = 3,
            passes   = 1,
            vibrancy = 0.1696,
        },
    },

    animations = {
        -- Off: transitions force full-rate redraws, which defeats VRR while they
        -- play. Set back to true to restore; the hl.animation() curves below are
        -- kept intact and simply ignored while this is false.
        enabled = false, -- was: enabled = yes, please :)
    },

    dwindle = {
        -- pseudotile = true,
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo   = false,

        -- Adaptive sync: stop redrawing a static screen at full refresh rate.
        vrr = 1,

        -- Required by the `fixlock` script. If hyprlock stops taking input, the
        -- ext-session-lock protocol keeps the compositor locked with no client
        -- to type into; without this, killing hyprlock cannot hand the lock to a
        -- fresh instance and the only way out is a reboot.
        allow_session_lock_restore = true,
    },
})


-- Beziers are hl.curve() now, and take point pairs instead of four flat floats.
hl.curve("easeOutQuint",   { type = "bezier", points = { { 0.23, 1 },    { 0.32, 1 }   } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 }   } })
hl.curve("linear",         { type = "bezier", points = { { 0, 0 },       { 1, 1 }      } })
hl.curve("almostLinear",   { type = "bezier", points = { { 0.5, 0.5 },   { 0.75, 1.0 } } })
hl.curve("quick",          { type = "bezier", points = { { 0.15, 0 },    { 0.1, 1 }    } })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 0.3,  bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 0.3,  bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 0.3,  bezier = "almostLinear", style = "fade" })


-- "Smart gaps" / "No gaps when only" -- uncomment if you want it.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })


---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,
        sensitivity  = 0.4, -- -1.0 to 1.0, 0 means no modification

        touchpad = {
            natural_scroll       = true,
            clickfinger_behavior = true, -- was 1; this is a bool now
            tap_and_drag         = false, -- was tap-and-drag = no; hyphen -> underscore
            drag_lock            = 0,     -- was no; this is an int now (0/1/2)
        },

        accel_profile = "flat",
    },
})

-- Per-device config
hl.device({
    name          = "logitech-wireless-receiver-mouse",
    sensitivity   = 0,
    accel_profile = "flat",
})

hl.device({
    name          = "yichip-wireless-device-mouse",
    sensitivity   = -0.1,
    accel_profile = "flat",
})


---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER"

hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C",      hl.dsp.window.close())
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd("firefox"))
hl.bind(mainMod .. " + space",  hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + F",      hl.dsp.window.fullscreen())
-- hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
-- hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

-- SUPER+P was window.pseudo(). Dropped -- dwindle's `pseudotile` is commented
-- out in the layout config below, so the dispatcher had nothing to toggle.
-- The key now belongs to hyprpicker, further down.

-- Plain SUPER+M (exit) stays unbound: too easy to hit by accident, and it
-- kills every window with no confirmation. SHIFT-guarded version instead.
-- Hyprland also falls back to a hardcoded SUPER+M exit if the config fails to
-- load, which is the real escape hatch.
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exit())

hl.bind("PRINT",         hl.dsp.exec_cmd("hyprshot -m window"))
hl.bind("SHIFT + PRINT", hl.dsp.exec_cmd("hyprshot -m region"))

-- exec_cmd runs through sh -c, so pipes and && still work as before.
-- Wrapper rather than an inline pipeline: it renders image entries as actual
-- thumbnails instead of "[[ binary data ... ]]". Absolute path because
-- Hyprland's exec environment does not carry ~/.local/bin on PATH.
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/cliphist-wofi"))
-- SUPER+X (wipe clipboard + history) removed: unguarded, silent, no undo, and
-- one key away from SUPER+C (close window). Run `cliphist wipe` in a terminal
-- for the rare case that needs it.

hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("killall waybar && waybar"))
hl.bind(mainMod .. " + L",         hl.dsp.exec_cmd("hyprlock"))

-- Color picker. -a copies to clipboard, -n notifies via swaync, -l gives
-- lowercase hex. Drop -n if the notification gets annoying.
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("hyprpicker -a -f hex -l -n"))

-- Blue-light filter manual override, on top of the hyprsunset.conf schedule.
-- `hyprctl hyprsunset temperature` prints the current value as a bare number,
-- so compare against it: warm if currently neutral, neutral otherwise.
-- Deliberately NOT `hyprctl hyprsunset identity` for the off half -- identity
-- clears the color matrix but leaves the query still reporting the old warm
-- value, so the toggle would latch on and never come back. 6000 is the
-- neutral default and round-trips correctly.
-- The schedule reasserts itself at the next profile boundary either way.
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd(
    "[ \"$(hyprctl hyprsunset temperature)\" -ge 5000 ] " ..
    "&& hyprctl hyprsunset temperature 4000 " ..
    "|| hyprctl hyprsunset temperature 6000"))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Workspaces 1-9 plus 0 -> 10. Twenty lines of hyprlang collapse into a loop.
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,           hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key,   hl.dsp.window.move({ workspace = i }))
end

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize with mainMod + LMB/RMB (was bindm)
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys (was bindel -> { locked = true, repeating = true })
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Cycle ASUS platform profile: quiet -> balanced -> performance.
-- Calls a root helper via a NOPASSWD sudoers rule and shows a notification.
-- If you later find which keycode Fn+F5 emits, rebind this to that instead.
hl.bind(mainMod .. " + F5", hl.dsp.exec_cmd("/home/naidoq/.local/bin/profile-cycle-notify"))

-- Requires playerctl (was bindl -> { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- All of yours were commented out. Kept that way, in the new syntax.
-- Note that rules now take a `name` and a `match` table.

-- Persistent workspace assignment. Unlike the exec_cmd workspace prefixes in
-- the autostart block, these apply however the app is launched -- launcher,
-- terminal, tray restore, or a link handler -- not just at login.
--
-- initialClass rather than class: class can change at runtime, initialClass is
-- frozen at window creation, so the rule still matches if the app renames
-- itself later. "silent" means the window goes there without stealing focus.
--
-- The regexes tolerate either capitalization because Electron and Spotify have
-- both shipped either over time. Verify against your actual windows with
-- hyprprop, or:  hyprctl clients -j | jq -r '.[].initialClass'
hl.window_rule({
    name      = "discord-to-9",
    match     = { initial_class = "^([Dd]iscord)$" },
    workspace = "9 silent",
})

hl.window_rule({
    name      = "spotify-to-8",
    match     = { initial_class = "^([Ss]potify)$" },
    workspace = "8 silent",
})

-- hl.window_rule({
--     name  = "float-kitty",
--     match = { class = "^(kitty)$", title = "^(kitty)$" },
--     float = true,
-- })

-- hl.window_rule({
--     name  = "suppress-maximize-events",
--     match = { class = ".*" },
--     suppress_event = "maximize",
-- })

-- hl.window_rule({
--     name  = "fix-xwayland-drags",
--     match = {
--         class      = "^$",
--         title      = "^$",
--         xwayland   = true,
--         float      = true,
--         fullscreen = false,
--         pin        = false,
--     },
--     no_focus = true,
-- })
