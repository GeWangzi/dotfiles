# Installing this setup on a new machine

Start to finish from a fresh Arch install, this is well under an hour, most of it
package downloads. Read `MACHINE.md` first if the target is not the same laptop —
it lists which parts are tied to specific hardware and which are safe anywhere.

Steps 1 through 5 get a working graphical session. Steps 6 onward are the things
that cannot be automated: credentials, wifi profiles, and audio tuning.

---

## 1. Get online

The reference machine has no ethernet port, so `iwctl` from the installer or a TTY
is the only way in:

```
iwctl
[iwd]# device list
[iwd]# station wlan0 scan
[iwd]# station wlan0 connect <SSID>
```

Check it worked before moving on — everything below downloads something:

```bash
ping -c3 archlinux.org
```

## 2. Base tools and the repo

```bash
sudo pacman -S --needed git stow zsh base-devel
git clone https://github.com/GeWangzi/dotfiles ~/dotfiles
```

## 3. Packages

Two lists, captured from the old machine with `pacman -Qqe` and `pacman -Qqm`.

Repo packages first:

```bash
sudo pacman -S --needed - < ~/dotfiles/pkglist-repo.txt
```

The AUR list needs a helper, and `paru` is itself on that list, so it has to be
built by hand before the list can be used:

```bash
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru && makepkg -si
paru -S --needed - < ~/dotfiles/pkglist-aur.txt
```

If a package has been dropped from the repos since the list was captured, pacman
refuses the whole transaction and names the offender. Delete that line and re-run;
it is not worth fighting.

**Keep the lists fresh.** They are snapshots and nothing regenerates them
automatically:

```bash
pacman -Qqe > ~/dotfiles/pkglist-repo.txt
pacman -Qqm > ~/dotfiles/pkglist-aur.txt
```

## 4. Dotfiles

Each top-level directory in the repo is a GNU stow package that mirrors the layout
under `$HOME`, so `stow -t ~ waybar` links `waybar/.config/waybar/*` into
`~/.config/waybar/`.

```bash
cd ~/dotfiles
stow -t ~ backgrounds chrome ember fontconfig fonts hyprland hyprlock hyprmocha \
          hyprpaper kitty local-bin quickshell skins spotify starship \
          systemd-user tmux waybar wireplumber zshrc
chsh -s /usr/bin/zsh
fc-cache -f
skinctl generate
```

There is no `wofi` package any more. Its stylesheet has to have the palette
inlined rather than imported, so the whole file is generated; the rules live in
`skins/.config/skins/templates/wofi.rules.css` and `skinctl` writes
`~/.config/wofi/style.css`.

`fc-cache -f` is not optional, for two reasons. The `fontconfig` package marks
CozetteVector as a monospaced family, that edit is applied when fonts are
scanned into the cache, and without it waybar and wofi fall back. The `fonts`
package also installs Silkscreen and DotGothic16, which nothing can see until
the cache is rebuilt. README's *Theme* section has the details.

kitty's body face is **DejaVu Sans Mono**, which comes from `ttf-dejavu` in
`pkglist-repo.txt` and is the one font here that is not self-hosted. If it is
missing, kitty does not fall back gracefully: fontconfig answers the miss with
Noto Sans CJK, kitty sizes its cell grid from that proportional face, and the
whole terminal comes out wide and airy. `rice-doctor` fails on this rather than
warning, because nothing else about the terminal is right until it is fixed.

    sudo pacman -S ttf-dejavu && fc-cache -f

`skinctl generate` is not optional either. The Quickshell shell reads
`skin.json`, kitty includes `skin.conf`, the
fallback hyprlock sources the hyprlang `skin.conf` and wofi reads a generated
`style.css` — none of which exist until skinctl has run once. The waybar and
hyprpaper packages are stowed for reverting but nothing starts them: the
shell draws the bar and the wallpaper itself. See README's *Skins* and *The
shell* sections.

`stow -t ~ */` also works and picks up everything, including `system/`. That is
harmless but pointless — `system/` is installed by its own script in step 5, not by
stow.

Two conflicts to expect on a machine that has been used for a while:

- **Stow refuses and lists real files where it wants to put symlinks.**
  `stow --adopt <package>` moves the existing file into the repo and replaces it
  with a link. Run `git diff` immediately afterwards: adopt silently overwrites the
  repo's version with whatever was on disk, and the fix is `git checkout` on
  anything that came out wrong.
- **`~/.config/.git` exists.** Delete it. It is a stale clone of this same repo from
  before the stow layout and it fights both stow and git.

## 5. System configuration

```bash
sudo bash ~/dotfiles/system/install.sh --dry-run   # read this output first
sudo bash ~/dotfiles/system/install.sh
```

What it does: writes the root-owned `/etc` files this repo carries, backing up
anything it replaces to `<file>.bak-<timestamp>`. What it deliberately does not do:
start anything, restart anything, or tune a running system. Everything takes effect
at the next boot. Several of these files govern audio gain and power management, and
restarting those services live has a history of leaving the machine worse than it
started.

It refuses to run on non-G14 hardware without `--force`. Read `MACHINE.md` before
overriding that — the NVMe and ASUS pieces are wrong elsewhere.

**The one thing it will not finish for you is GRUB.** It rewrites the two
`GRUB_CMDLINE` lines in `/etc/default/grub` and then stops, printing the command to
run rather than running it. Before you run that command, check the `rootfstype`:

```bash
findmnt -no FSTYPE /       # if this is not ext4, edit /etc/default/grub now
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

A wrong `rootfstype` stops the machine booting, which is why a human reads that line
before the boot config is regenerated.

On a machine that boots with systemd-boot instead of GRUB, the script says so and
skips it; put `zswap.enabled=0 nvme_core.default_ps_max_latency_us=0` in the kernel
cmdline there instead.

## 6. Enable services

Nothing above enables anything. System level:

```bash
sudo systemctl enable NetworkManager iwd bluetooth panel-od-off
sudo systemctl enable power-profiles-daemon battery-charge-limit
sudo systemctl enable nvidia-suspend nvidia-resume nvidia-hibernate
sudo systemctl enable docker          # optional
sudo systemctl enable sing-box        # only after step 7
```

User level:

```bash
systemctl --user enable hyprpolkitagent hyprsunset lowbattery.timer
systemctl --user enable wireplumber pipewire-pulse
```

`ollama.service` is intentionally left disabled; it is started by hand when needed.

## 7. Carry the secrets across

None of this is in the repo, because the repo is public. None of it is recoverable
if the old disk dies either, so it is worth keeping an offline copy independently of
this migration.

| What | Where it goes | Notes |
|---|---|---|
| sprite art | `~/dotfiles/quickshell/.config/quickshell/assets/` | gitignored (personal-use art); tarball lives in `~/Backups/quickshell-assets-*.tar.gz` on the old machine. Without it the shell runs with dashed placeholder slots and no route backgrounds |
| `secrets.env` | `~/.config/secrets.env`, mode 0600 | API keys; sourced by `.zshrc` and `.zprofile` |
| sing-box config | `/etc/sing-box/config.json`, mode 0640 `root:sing-box` | holds the VLESS server address and UUID |
| wifi profiles | `/etc/NetworkManager/system-connections/` | ~32 profiles, PSKs in plaintext |
| `connectvm` | `~/.local/bin/connectvm` | RDP host address and username |
| ssh / gpg keys | `~/.ssh/`, `~/.gnupg/` | |
| cloud credentials | `~/.aws/`, `~/.docker/config.json` | |

Copy them over ssh or a USB stick. A full NetworkManager backup from the old machine
is at `/root/nm-backup-2026-08-16.tar.gz`; restoring it as root is faster than
re-entering networks by hand, but re-entering the three or four that actually matter
is also fine.

After copying the sing-box config, check that its `experimental.cache_file` block
survived the trip:

```bash
sudo jq -r 'paths | select(.[-1] == "cache_file") | join(".")' /etc/sing-box/config.json
# expect: experimental.cache_file
```

Without it the `geoip-cn` and `geosite-cn` rule sets are re-downloaded at every
start, and a failed download silently routes China-bound traffic through the proxy
instead of direct. See `MACHINE.md`.

## 8. Tune the microphone

Gain staging is per-codec and cannot be carried as a file. On the ALC285, these are
the values that sounded right, found by ear and confirmed by other people on a voice
call:

```bash
sudo pacman -S alsa-utils
alsamixer          # F4 switches to the capture view
#   Internal Mic Boost: 1   (10 dB — the default is 3, which is 30 dB)
#   Capture:            50  (20.25 dB — the default is 63, the maximum)
sudo alsactl store
```

`alsactl store` writes `/var/lib/alsa/asound.state`, which `alsa-restore.service`
replays at boot. **Retuning later means running `sudo alsactl store` again** or the
change is lost at the next reboot.

The `wireplumber` stow package from step 4 installs the drop-in that stops
WirePlumber driving the hardware `Capture` control to implement volume changes.
Without it, both analog stages snap back to maximum on any route re-apply — plugging
in headphones, connecting a Bluetooth headset, or an app changing input volume — not
just at boot.

**Never tune this mic with `wpctl set-volume`.** It applies software gain and drives
the hardware `Capture` control straight back to 63.

Known gap: `alsa-restore` runs early at boot, before WirePlumber starts, so nothing
re-applies if WirePlumber clobbers the values during its own startup. If the mic
sounds bad after a reboot, check it:

```bash
amixer -c 2 sget 'Internal Mic Boost'      # 3 [30.00dB] means exactly this happened
```

## 9. Reboot and check

```bash
sudo reboot
```

Log in on tty1 — there is no display manager; `.zprofile` execs `start-hyprland`
when it sees a login shell on tty1. Then:

```bash
rice-doctor                                         # shell up, fonts seen, log clean
bash ~/.local/bin/netcheck.sh                       # link, then proxy, layer by layer
sudo smartctl -a /dev/nvme0n1 | grep -i "power cycles"   # baseline for the NVMe fix
iw dev wlan0 get power_save                         # expect: off
amixer -c 2 sget 'Internal Mic Boost'               # expect: 1 [10.00dB]
```

The power cycle count is the number to write down. It should climb by single digits
over hours on battery. If it races upward, the NVMe workaround is not taking effect
— check that the grub step actually ran.

Also worth testing now rather than during an emergency: `Alt+SysRq+H`, then
`dmesg | tail`. If a help line appears, the SysRq escape from a hung system works
(see `MACHINE.md`). If not, the F-row is in media mode and `Fn` is needed too.

## 10. Set up backups

Do not skip this because the machine feels finished. The old machine ran without any
backup at all on a drive with a known controller hang, which is the single largest
risk documented in `MACHINE.md` — read the disk breakdown there first, because the
set worth backing up is about 19 GiB, not the 293 GiB the home directory reports.

`borg`, `borgmatic` and `restic` are all in the repos. For a local external drive:

```bash
sudo pacman -S --needed borg borgmatic
borg init --encryption=repokey-blake2 /mnt/backup/borg
sudo systemctl enable --now borgmatic.timer
```

Two things people get wrong here. Write the repository passphrase down somewhere off
the machine — a repokey backup you cannot decrypt is not a backup, and the key lives
in the repo you are trying to protect. And test a restore before trusting it:

```bash
borgmatic extract --archive latest --path home/naidoq/Documents --destination /tmp/rt
diff -r /tmp/rt/home/naidoq/Documents ~/Documents
```

Include `/etc` in the source directories. `system/` in this repo only covers the
files that were copied into it by hand.

---

## Keeping this repo honest

When a fix touches a root-owned file on the machine, copy it into `system/etc/` and
commit, or it exists on one disk only. The check for whether that has been kept up:

```bash
sudo bash ~/dotfiles/system/install.sh --dry-run
```

Every line that says `already matches` is a file in sync. Anything else is drift
between the repo and the live system.
