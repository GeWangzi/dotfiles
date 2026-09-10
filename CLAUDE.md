# dotfiles

GNU Stow packages for one Arch laptop (Hyprland + Quickshell). Every top-level
directory except `system/` and `docs/` is a stow package mirroring `$HOME`, and
the links are live: editing a file here edits the running config.

## Commands

```sh
rice-doctor                          # restart the shell, check its log — the test for any QML/config change
skinctl lint                         # check skins.toml against the colour rules
skinctl generate                     # re-render palette outputs after editing skins.toml
sudo bash system/install.sh --dry-run   # compare system/ against live /etc; never run without --dry-run first
```

## Layout

- `quickshell/` — the shell (bar, lock, launcher, OSD, power/details menus, notifications)
- `skins/` — `skins.toml` is the only place a colour is written; templates render from it
- `hyprland/` — `hyprland.lua` is the active config; `hyprland.conf` is the fallback and must stay minimal
- `system/` — copies of root-owned `/etc` files, installed by `install.sh`, not stow
- `local-bin/` — scripts in `~/.local/bin`

## Conventions

- No unnecessary edits. Every change or addition to the machine needs a stated reason. If it
  addresses an issue, it must be the best way to address that issue, not just one that works.
- Small commits: one feature or fix per commit, with a message that says what changed and why.
- Never `git checkout` / `git switch` in this checkout. Use `git worktree add ../dotfiles-<branch>`.
- Colours: edit `skins.toml`, never the generated files under `~/.local/state/skins`.
- QML: blink with a Timer, never an animation; poll only while a surface is visible.
- Restart the shell with `pkill -x qs`, not `qs kill`.

## Testing

A QML or Hyprland change is complete only when `rice-doctor` passes. A skin
change is complete only when `skinctl lint` passes.

## Gotchas

- Hyprland, Quickshell, and kitty pick up skin changes live; hyprlock at next lock.
- Kitty resolves fonts at startup; font changes need a new window.
- If the shell dies while locked, `hyprlock` from a TTY recovers.