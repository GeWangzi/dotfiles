# Bootstrapping a new machine

This repo carries the whole desktop setup except for the parts that are secret
or hardware-serial. Working from a fresh Arch install, the sequence below gets
back to a usable Hyprland session in well under an hour, most of which is
package downloads.

The target machine this was written for is an ASUS ROG Zephyrus G14 (GA401QM):
Ryzen 7 5800HS, NVIDIA hybrid graphics, MT7921 wifi, WD Green SN350 NVMe,
Realtek ALC285 audio, no ethernet port. On other hardware everything in the
stow packages still applies, but read the notes in `system/install.sh` before
running it.

## 1. Network, on a machine with no ethernet port

The installer's `iwctl` is the only way in:

```
iwctl
[iwd]# device list
[iwd]# station wlan0 scan
[iwd]# station wlan0 connect <SSID>
```

## 2. Base tools and the repo

```bash
sudo pacman -S --needed git stow zsh base-devel
git clone https://github.com/GeWangzi/dotfiles ~/dotfiles
```

## 3. Packages

Two lists, captured from the old machine:

```bash
cd ~/dotfiles
sudo pacman -S --needed - < pkglist-repo.txt
```

`pkglist-aur.txt` needs an AUR helper, and `paru` is itself in that list, so it
has to be built first:

```bash
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru && makepkg -si
paru -S --needed - < ~/dotfiles/pkglist-aur.txt
```

Regenerate both lists whenever the package set changes meaningfully:

```bash
pacman -Qqe > ~/dotfiles/pkglist-repo.txt
pacman -Qqm > ~/dotfiles/pkglist-aur.txt
```

## 4. Dotfiles

```bash
cd ~/dotfiles
stow -t ~ backgrounds chrome hyprland hyprlock hyprmocha hyprpaper kitty \
          local-bin nvim spotify starship systemd-user tmux waybar \
          wireplumber wofi zshrc
chsh -s /usr/bin/zsh
```

`stow -t ~ */` also works and picks up everything, including `system/`, which
is harmless but pointless -- `system/` is installed by its own script, not by
stow.

Two conflicts to expect on a machine that has been used for a while:

* If `~/.config` contains real files where a package wants symlinks, stow
  refuses and lists them. `stow --adopt` moves the existing file into the repo
  and replaces it with a link; check `git diff` afterwards, because adopt
  silently overwrites the repo's version with whatever was on disk.
* Delete `~/.config/.git` if it exists. It is a stale clone of this same repo
  from before the stow layout, and it will confuse both stow and git.

## 5. System configuration

```bash
sudo bash ~/dotfiles/system/install.sh --dry-run   # read this first
sudo bash ~/dotfiles/system/install.sh
```

It writes `/etc` files only -- no service is started, nothing is tuned live,
and every file it replaces is backed up alongside itself. The script prints the
remaining manual steps when it finishes; they are also listed below.

## 6. The things that cannot live in a public repo

Carry these by hand from the old machine. Nothing else in this list is
recoverable if the old disk dies, so it is worth keeping an offline copy.

| What | Where it lives | Why it is not here |
|---|---|---|
| `~/.config/secrets.env` | mode 0600, sourced by `.zshrc` and `.zprofile` | API keys |
| `/etc/sing-box/config.json` | mode 0640 `root:sing-box` | VLESS server address and UUID |
| `/etc/NetworkManager/system-connections/` | root-only | ~32 wifi profiles with plaintext PSKs |
| `~/.local/bin/connectvm` | | RDP host address and username |
| `~/.ssh/`, `~/.gnupg/` | | keys |
| `~/.aws/`, `~/.docker/config.json` | | credentials |

A full NetworkManager backup from the old machine is at
`/root/nm-backup-2026-08-16.tar.gz`.

## 7. Enable services

```bash
sudo systemctl enable NetworkManager iwd tlp bluetooth panel-od-off
sudo systemctl enable nvidia-suspend nvidia-resume nvidia-hibernate
sudo systemctl enable docker          # optional
sudo systemctl enable sing-box        # only once its config exists

systemctl --user enable hyprpolkitagent hyprsunset swaync lowbattery.timer
systemctl --user enable wireplumber pipewire-pulse
```

## 8. Microphone

Gain staging is per-codec and is not portable as a file. On the ALC285 the
values that sounded right were found by ear:

```bash
sudo pacman -S alsa-utils
alsamixer          # F4 for the capture view
#   Internal Mic Boost: 1   (10 dB, not the default 3 / 30 dB)
#   Capture:            50  (20.25 dB, not the default 63 / max)
sudo alsactl store
```

The `wireplumber` stow package installs the drop-in that stops WirePlumber
resetting both analog stages to maximum whenever audio routing changes. Without
it the tuning survives until the first time headphones are plugged in.

Never tune this mic with `wpctl set-volume` -- it does software gain and drives
the hardware `Capture` control straight back to 63.

## 9. Known quirks that come with this setup

Not bugs to re-diagnose; they are documented behaviour of this configuration.

* **Lock screen goes deaf after suspend.** hyprlock keeps drawing but ignores
  the keyboard. Switch to a TTY with Ctrl+Alt+F2, log in, run `fixlock`, then
  Ctrl+Alt+F1. This depends on `misc:allow_session_lock_restore = true` staying
  in the Hyprland config and on `~/.local/bin` being on `PATH` in a TTY login
  shell -- do not "clean up" either.
* **Hyprland's active config is `hyprland.lua`, not `hyprland.conf`.** Binds
  dispatch through `__lua`, so `hyprctl dispatch` calls take the
  `hl.dsp.foo(...)` form there.
* **"The internet stopped working" is usually sing-box, not wifi.** Run
  `netcheck.sh`, which tests the link, then pings the gateway and 1.1.1.1 with
  `-I wlan0` to bypass `tun0`, then makes a real HTTPS request through the
  tunnel. Layers 0-2 passing with layer 3 failing means
  `sudo systemctl restart sing-box`, not a reboot. `systemctl is-active
  sing-box` reports active while the tunnel passes no traffic and is useless
  here.
* **sing-box loses a race with the uplink at boot.** It starts before wlan0 has
  a default route, builds its `auto_route` state against nothing, and never
  rebuilds it. The `Wants=network-online.target` drop-in in `system/` helps but
  has not fully fixed it; the reliable recovery is a service restart.
* **Two harmless boot log lines under iwd:** `IWD device named wlan0 is not a
  Wifi device` (a startup race that self-corrects) and `error setting IPv4
  forwarding` on the `/net/connman/iwd/0` P2P device.
* **iwd drops WiFi Direct / Miracast and `nmcli device wifi hotspot`.** Nothing
  in this setup used them.
* **Random total lockups with the drive LED flashing** mean the NVMe controller
  failed to return from a low-power state. The `99-nvme.conf` and grub
  parameters in `system/` are the fix. The metric that proves it is working is
  the power-cycle count, not the absence of crashes:
  `sudo smartctl -a /dev/nvme0n1 | grep -i "power cycles"`. On the old machine
  the baseline was 214,757 and it was climbing by roughly 21 an hour.
