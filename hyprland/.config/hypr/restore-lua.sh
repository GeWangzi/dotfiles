#!/usr/bin/env bash
# Hyprland Lua config recovery.
# Run from a TTY (Ctrl+Alt+F2) if Hyprland fails to start.
#
#   ~/.config/hypr/restore-lua.sh          restore the pristine original Lua config
#   ~/.config/hypr/restore-lua.sh --conf   disable Lua entirely, fall back to hyprland.conf
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "--conf" ]; then
    [ -f hyprland.lua ] && mv -v hyprland.lua "hyprland.lua.disabled-$(date +%Y%m%d-%H%M%S)"
    echo "Lua config disabled. Hyprland will fall back to hyprland.conf."
    exit 0
fi

if [ ! -f hyprland.lua.original ]; then
    echo "ERROR: hyprland.lua.original is missing. Use --conf to fall back to hyprland.conf." >&2
    exit 1
fi

[ -f hyprland.lua ] && cp -v hyprland.lua "hyprland.lua.rejected-$(date +%Y%m%d-%H%M%S)"

# hyprland.lua is normally a stow symlink into ~/dotfiles. Copying onto it
# would write straight through the link and silently overwrite the tracked
# config, so drop the link first and restore a plain local file instead. The
# repo copy is then left untouched, and re-stowing puts the link back once the
# real config is fixed.
was_link=no
if [ -L hyprland.lua ]; then
    was_link=yes
    rm -f hyprland.lua
fi

cp -v hyprland.lua.original hyprland.lua
chmod 644 hyprland.lua
echo
echo "Restored the pristine original Lua config. Log in again."
if [ "$was_link" = yes ]; then
    echo
    echo "NOTE: hyprland.lua was a stow symlink and is now a plain local file."
    echo "      After repairing the config, put it back under version control:"
    echo "          cp ~/.config/hypr/hyprland.lua ~/dotfiles/hyprland/.config/hypr/hyprland.lua"
    echo "          rm ~/.config/hypr/hyprland.lua"
    echo "          stow -d ~/dotfiles -t ~ -R hyprland"
fi
