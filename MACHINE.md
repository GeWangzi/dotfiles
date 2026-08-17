# The machine these dotfiles were built for

Everything in this repo assumes one laptop. Most of it is portable, but a handful
of files exist purely to work around this specific hardware, and knowing which is
which is the difference between a clean install elsewhere and a machine that will
not boot. This document is the reference; `INSTALL.md` is the procedure.

Captured 2026-08-17. Anything with a number in it drifts, so treat the figures as
"what it was" rather than "what it is".

## Identity

| | |
|---|---|
| Model | ASUS ROG Zephyrus G14, GA401QM (`ROG Zephyrus G14 GA401QM_GA401QM`) |
| Board | GA401QM |
| BIOS | `GA401QM.415`, dated 2023-08-11 |
| OS | Arch Linux, kernel `7.1.5-arch1-2` |
| Firmware mode | UEFI |
| Hostname user | `naidoq` |

## Hardware

**CPU** — AMD Ryzen 7 5800HS, 8 cores / 16 threads, 403 MHz to 4465 MHz.

**Memory** — 38 GiB usable.

**Graphics — two GPUs, and this matters more than anything else here.**

| Bus | Device | Driver |
|---|---|---|
| `01:00.0` | NVIDIA GA106M, GeForce RTX 3060 Mobile / Max-Q | `nvidia-open` 610.43.03 |
| `04:00.0` | AMD Cezanne, Radeon Vega integrated | amdgpu (in-kernel) |

The session deliberately runs on the AMD iGPU only. `~/.zprofile` sets
`AQ_DRM_DEVICES` to the AMD card's stable by-path node before launching Hyprland,
because otherwise Hyprland brings up a second DRM backend on the NVIDIA card, holds
`/dev/nvidia0` open for the life of the session, and the dGPU can never
runtime-suspend — about 9.4 W burned at 0% utilization.

That alone is not enough. libglvnd scans `egl_vendor.d` in filename order and
`10_nvidia.json` sorts ahead of `50_mesa.json`, so EGL would still load
`libEGL_nvidia` and pin the card awake. `.zprofile` therefore also pins
`__EGL_VENDOR_LIBRARY_FILENAMES` to the Mesa vendor file.

The cost, and it is a real one: **the USB-C / DisplayPort output is wired to the
NVIDIA card and does not work while this is set.** HDMI and the internal panel hang
off the AMD card and are unaffected. CUDA and Vulkan go through different loaders
and are not affected either, so ollama still sees the dGPU.

**Display** — internal eDP-1, 1920x1080, 157 DPI. The panel will do 143.98 Hz; the
Hyprland config pins it to 59.99 Hz at scale 1.5. If a high refresh rate is wanted,
that is the line to change, not a driver problem.

**Audio** — Realtek ALC285 on ALSA card 2 (`04:00.6`, AMD Ryzen HD Audio). Card 0 is
NVIDIA HDMI audio, card 1 is AMD HDMI/DP audio; neither carries the speakers or the
internal mic array. The mic gain staging is tuned by ear and is not portable — see
`INSTALL.md` step 8 and the warning in it about `wpctl set-volume`.

**Wifi** — MediaTek MT7921 (`02:00.0`, `mt7921e`), driven through NetworkManager
with the **iwd** backend rather than wpa_supplicant, set in
`/etc/NetworkManager/conf.d/wifi-backend.conf`. That file overrides a stale
`wifi.backend=wpa_supplicant` still sitting in the main `NetworkManager.conf` — edit
the conf.d file, never the main one, and note that a backend change needs a full
`systemctl restart NetworkManager`, not a reload.

**There is no ethernet port.** A text console (Ctrl+Alt+F2) is the only fallback if
wifi breaks, which is why several recovery tools are kept working from a bare TTY.

**Storage** — WD Green SN350 2TB, firmware `33006000`, controller `15b7:5014`. This
is a DRAM-less QLC drive leaning on a 128 MiB host memory buffer, and it is the
single most troublesome component in the machine. See "The NVMe hang" below.

```
nvme0n1  1.8T
├─p1       1G  vfat  /boot
├─p2      50G  ext4  /
└─p3     1.8T  ext4  /home
```

**Swap** — `zram0`, 4 GiB, zstd. There is no swap partition and no swap file.

Worth knowing: `nvidia-hibernate.service` is enabled, but hibernation cannot
actually work with zram as the only swap device — there is nowhere to write the
image. The nvidia suspend/resume/hibernate trio was enabled while chasing the
lockups described below and left in place because it is correct configuration, not
because hibernate is in use.

**Battery** — ASUS Battery, 76.0 Wh design capacity, 59.0 Wh full charge as
measured, so roughly 78% health.

## How the session starts

There is no display manager. Login is a plain `getty` on tty1, and `~/.zprofile`
execs `start-hyprland` when it sees a login shell on `/dev/tty1` with no `DISPLAY`.
Hyprland is 0.56.1.

The login shell is zsh. `~/.bash_profile` and `~/.bashrc` are deliberately left in
place and working, so `chsh -s /usr/bin/bash` is a complete escape hatch if the zsh
path ever breaks.

**Hyprland's active config is `hyprland.lua`, not `hyprland.conf`.** Binds show
`dispatcher: __lua`, and `hyprctl dispatch` calls take the `hl.dsp.foo(...)` form
there rather than the classic keywords. `hyprland.conf` is kept alongside it and is
still readable as documentation of the pre-Lua state, but editing it changes
nothing.

## Services

Enabled at the system level:

```
NetworkManager  iwd  tlp  bluetooth  docker
sing-box  panel-od-off
nvidia-suspend  nvidia-resume  nvidia-hibernate
```

Enabled for the user:

```
hyprpolkitagent  hyprsunset  swaync  wireplumber  pipewire-pulse
lowbattery.timer
```

`ollama.service` is installed with a drop-in (`OLLAMA_HOST=0.0.0.0:11434`,
`OLLAMA_MODELS=/home/ollama-models`, `ProtectHome=false`) but is **not** enabled;
it gets started by hand when wanted. The models live outside `$HOME` at
`/home/ollama-models`, which is why the drop-in has to turn `ProtectHome` off.

## The NVMe hang

The defining bug of this machine, and the reason several files in `system/` exist.

The laptop would lock up at random — no input, no way to reach a TTY, power button
only. Three crashes in five hours at the worst, with unclean shutdowns going back
weeks and accelerating.

**The clue was the front-panel LED.** Three indicators, left to right: lightbulb,
battery, cylinder. The cylinder is drive activity, and it flashed continuously
through every freeze. That single observation identified the subsystem and was
worth more than any log.

The logs are always empty, and that is expected rather than a missing clue:
journald cannot write when the disk it writes to has hung. Every process blocks in
D state on the root filesystem, which is why the machine looks completely dead while
the CPU is fine. One crash showed four minutes of `systemd-journald: Under memory
pressure, flushing caches` and was initially misread as memory exhaustion — the
causation runs the other way, dirty pages could not write back to a stalled drive so
the page cache ballooned.

**Root cause:** two aggressive power savers stacked on a controller that does not
reliably survive the transitions. TLP ran with stock defaults, so
`RUNTIME_PM_ON_BAT=auto` and `PCIE_ASPM_ON_BAT=powersupersave` dropped the NVMe to
D3cold; and APST had `nvme_core.default_ps_max_latency_us=100000`, permitting the
drive's PS3 and PS4 states with their 11 ms and 39 ms exit latencies. Occasionally
the controller does not come back.

SMART media health is a red herring here — 1% used, 100% spare, zero errors. The
number that tells the story is the power cycle count:

```
Power On Hours:   10,295
Power Cycles:     214,757     ~21 controller power cycles per hour
Unsafe Shutdowns: 823
```

A normal laptop drive shows a few thousand over its entire life.

**Ruled out, do not re-chase:** suspend/resume is not the trigger (one crash came 46
minutes into a boot with no suspend at all), and the kernel is not either (the first
unclean shutdown predates the 7.0.11 → 7.1.5 upgrade). This is also distinct from
the hyprlock-goes-deaf bug below, which still lets you reach a TTY.

**The fix** is `/etc/tlp.d/99-nvme.conf` plus the kernel command line, both carried
in `system/`. The metric for whether it is working is the power cycle count, not the
absence of crashes:

```bash
sudo smartctl -a /dev/nvme0n1 | grep -i "power cycles"
```

Baseline was 214,757 on 2026-08-14. After hours on battery it should climb by single
digits. If it still races upward, something other than TLP is driving D3cold.

Still outstanding: check whether WD has released SN350 firmware newer than
`33006000`, since several controller hang bugs on this drive were fixed in firmware.

## Other quirks that come with this machine

**The lock screen goes deaf after suspend.** Locking and then suspending leaves
hyprlock visible but ignoring the keyboard (Hyprland 0.56.1, hyprlock 0.9.6).
Instrumented repro confirmed the input devices tear down on suspend, return about
two seconds after resume, and stay healthy — but hyprlock's ext-session-lock surface
never regains keyboard focus, and logs `Invalid key down event (stray release
event?)` for anything typed. Relaunching hyprlock fixes it.

The chosen response is manual, not automated: Ctrl+Alt+F2, log in, run `fixlock`,
Ctrl+Alt+F1. An automatic resume hook was built, tested working, and then
deliberately removed. Do not re-add it or other hypridle sleep hooks.

Two things exist only to keep `fixlock` working and must not be cleaned up:
`misc:allow_session_lock_restore = true` in both `hyprland.lua` and `hyprland.conf`
(without it, killing hyprlock leaves the compositor locked with no client and only a
reboot escapes), and the explicit `PATH` block in `.zprofile` (without it
`~/.local/bin` is not on `PATH` in a TTY login shell, since `.zshrc` only exports it
for interactive shells).

**"The internet stopped working" is usually sing-box, not wifi.** On 2026-08-16 a
session died this way and a reboot appeared to fix it, but the logs showed wlan0
stayed associated and held its DHCP lease throughout — what had stalled was
sing-box's VLESS outbound, with connections hanging 1m21s to 1m41s and DNS failing
for `api.anthropic.com`. The same stalls appear in the 18-hour boot before the iwd
switch (30 of them, one at 4m8s), so this predates iwd and is not caused by it.

`systemctl is-active sing-box` is useless for diagnosing it — the service reports
active while the tunnel passes no traffic. Run `netcheck.sh` instead: it tests the
link, then pings the gateway and 1.1.1.1 with `-I wlan0` to bypass `tun0`, then
makes a real HTTPS request through the tunnel. Layers 0-2 passing with layer 3
failing means `sudo systemctl restart sing-box`, not a reboot.

**sing-box loses a race with the uplink on every boot.** Journal signature:

```
Finished Network Manager Wait Online.        <- returns in the same second
Started sing-box service.
sing-box: ERROR network: missing default interface
(5s later) NetworkManager: dhcp4 (wlan0): new lease, address=192.168.1.4
```

sing-box builds its `auto_route` / `auto_detect_interface` tun0 state against a
nonexistent uplink and never rebuilds it, so every dial fails with `no route to
internet`, and because DNS uses a `detour: proxy` server, name resolution dies with
it. Only a service restart recovers it.

`After=network-online.target` buys nothing here, because wait-online waits for
NetworkManager *startup-complete*, and under the iwd backend NM declares startup
done before wlan0 associates. As of 2026-08-17 the only drop-in actually present is
`sing-box.service.d/override.conf` containing `Wants=network-online.target`, which
for the same reason does not fix it. **Treat this as still open.** A working fix
needs wait-online overridden to `nm-online -q --timeout=60` and an `ExecStartPre`
that polls `ip route show default`.

Separately, `/etc/sing-box/config.json` has no top-level `experimental.cache_file`
block, so the remote `geoip-cn` / `geosite-cn` rule sets are re-downloaded at every
start. When that download fails the rule sets are absent, and all China-destined
traffic silently goes through the proxy instead of direct.

**Harmless iwd log lines, not worth chasing:** `IWD device named wlan0 is not a Wifi
device` (a NetworkManager/iwd startup race that self-corrects) and `error setting
IPv4 forwarding` on the `/net/connman/iwd/0` P2P device.

**Gone under iwd,** though nothing here used them: WiFi Direct / Miracast, and
`nmcli device wifi hotspot`.

**The eduroam profile has never been tested under iwd.** It is PEAP/MSCHAPv2, and
iwd validates server certificates more strictly than wpa_supplicant did. If it will
not associate on campus, set `802-1x.ca-cert` and `802-1x.domain-suffix-match` on
that profile, or revert to wpa_supplicant for the trip.

## What in this repo is hardware-specific

Safe anywhere — the stow packages. Configs for Hyprland, waybar, wofi, kitty, nvim,
zsh, tmux, starship, and the scripts in `local-bin`. Worst case a keybind refers to
hardware that is not there.

Tied to this laptop — most of `system/`:

| File | Tied to |
|---|---|
| `tlp.d/99-nvme.conf`, the grub NVMe parameter | the WD SN350 controller specifically |
| `systemd/system/panel-od-off.service` | an ASUS `asus-nb-wmi` sysfs path |
| `tlp.d/02-profile.conf` | the G14's platform-profile fan curves |
| `wireplumber` soft-mixer drop-in | the ALC285 node name |
| `rootfstype=ext4` in the grub cmdline | this machine's root filesystem |

`system/install.sh` checks the DMI product name and refuses to run on non-G14
hardware unless given `--force`, for exactly these reasons.
