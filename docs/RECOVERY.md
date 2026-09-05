# Recovery

The recovery path is a TTY, the network, and Claude Code in this repo. There is
no rescue desktop.

1. `Ctrl+Alt+F3`, log in. The shell, greeting and `~/.local/bin` all work here.
2. Get online. `nmtui`, or `nmcli device wifi connect <ssid> --ask`.
3. `netcheck.sh` — link, then tunnel. The proxy stays "active" while dead;
   `sudo systemctl restart sing-box` if layer 3 fails with wifi fine.
4. `cd ~/dotfiles && claude`, and describe the symptom: what you did last,
   what the screen shows, `journalctl -b -p err --no-pager | tail -40`.

Hyprland reads `hyprland.conf` when `hyprland.lua` is absent. To prove the
compositor itself starts: `mv ~/.config/hypr/hyprland.lua{,.off}`, log in on
tty1 again; `cd ~/dotfiles && stow -R hyprland` puts the link back.

**If `claude` itself is broken**, reinstall to `~/.local/bin`:

```
curl -fsSL https://claude.ai/install.sh | bash
```

**Other branches: use a worktree, never `git checkout` in `~/dotfiles`.** Every
stow link points into this checkout, so switching branches here swaps the live
config under the running session.

```
git worktree add ../dotfiles-<branch> <branch>
```
