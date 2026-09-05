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

The WirePlumber soft-mixer drop-in that protects that tuning is confirmed working as
of 2026-08-17 — `wpctl inspect` on the capture node reports
`api.alsa.soft-mixer = "true"` for `alsa_input.pci-0000_04_00.6.analog-stereo`, so
WirePlumber is doing volume in software and is not driving the hardware controls.

That matters for diagnosis, because the gain can still be wrong for a different
reason. On a fresh boot on 2026-08-17 the values read `Internal Mic Boost 0` and
`Capture 63`, not the tuned `1` and `50`, even though `alsa-restore.service` had
completed successfully. With soft-mixer confirmed on, nothing was clobbering the
controls live — the bad values are stored in `/var/lib/alsa/asound.state` itself,
written there by the `ExecStop=alsactl store` that `alsa-restore` runs at shutdown,
at some point when the values were already wrong.

So there are two distinct failures with the same symptom, and they are told apart by
whether soft-mixer is on:

```bash
wpctl inspect <capture-node-id> | grep soft-mixer   # "true" -> stored state is stale
amixer -c 2 sget 'Internal Mic Boost'               # what is actually loaded
```

If soft-mixer is on and the values are wrong, the fix is to set them once and run
`sudo alsactl store` — they will stick, because nothing is fighting them. Building a
service to re-apply after WirePlumber starts is the fix for the *other* failure and
would be treating the wrong cause here.

**Wifi** — MediaTek MT7921 (`02:00.0`, `mt7921e`), interface **`wlp2s0`**, driven
through NetworkManager on its stock **wpa_supplicant** backend.

The interface was `wlan0` until 2026-08-25. iwd ships `80-iwd.link`, which pins
kernel names; removing the package removed that file, so systemd's predictable
naming took over on the next boot (`mt7921e 0000:02:00.0 wlp2s0: renamed from
wlan0`). Nothing here hardcodes the name any more — `wifi-doctor` and
`netcheck.sh` both walk `/sys/class/net/*/wireless` — but it is the first thing
to suspect if some older script suddenly reports no wifi.

Wifi power saving is **on**, which is NetworkManager's default. It was forced off
until 2026-08-25 because the MT7921 had latency spikes on an idle link. If that
returns — wifi dies when idle, revives on the first ping — the fix is one drop-in
with `[connection] wifi.powersave=2` and nothing else. There is no drop-in configuration at all:
`/etc/NetworkManager/conf.d/` is empty and `NetworkManager.conf` is the packaged
file, untouched. `wpa_supplicant.service` is *not* enabled — NetworkManager starts
it on demand through D-Bus activation (`fi.w1.wpa_supplicant1`), which is how Arch
ships it. Enabling that unit by hand is a divergence, not a fix.

Keep it empty. Every setting that used to live in `conf.d` was a workaround for
something else, each drop-in silently overrode the one before it alphabetically,
and the net effect was a wifi stack nobody could reason about. If a setting is
genuinely needed, one file with one setting and a comment saying why.

`networkmanager` is explicitly installed and listed in `pkglist-repo.txt`. It
was dep-marked until 2026-08-21, when removing `network-manager-applet` with
`-Rns` cascaded and took NetworkManager, `libnma` and `nmcli` with it —
`system-connections/` survived, but nothing on this machine could have
configured wifi after a reboot. Marked explicit so that cannot repeat.

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
measured, so roughly 78% health. Charging stops at 80%, enforced by
`battery-charge-limit.service`; see "The battery charge limit" below.

## What is actually on the disk, and what would hurt to lose

`/home` reads as 293 GiB, which makes backing it up sound like a project. It is not
— almost all of that is reconstructible:

```
188G  .local/share/Steam        redownloadable
 31G  .local/share/Trash        deleted files nobody emptied
 29G  .cache                    disposable by definition
 ~8G  .npm .gradle .m2 .rustup go     dependency caches, rebuildable
```

The set that cannot be recreated, measured together, comes to **19 GiB**:

```
7.7G  sandbox          1.7G  .thunderbird     592M  Pictures
4.4G  work             1.5G  Videos           181M  .claude
1.2G  .minecraft       923M  .mozilla          53M  dotfiles
641M  Documents        176K  .gnupg            36K  .ssh
```

Plus `~/.config/secrets.env` and `~/.aws`, which are tiny and matter most.

**There is no backup of any of this.** No borg, restic, timeshift, snapper or
rsnapshot is installed, `lsblk` shows nothing but the internal NVMe, `fstab` has no
external mount, and no USB storage appears anywhere in the journal. On a machine
whose defining bug is a storage controller that occasionally does not come back,
that is the largest single risk here — larger than any of the bugs documented below,
because every one of those is recoverable and this is not.

19 GiB fits on any external drive, and borg deduplicates and compresses it well
below that. `borg`, `borgmatic` and `restic` are all packaged. The partial mitigation
that needs no hardware is pushing the ~20 git repositories under `work/` and
`sandbox/` to remotes:

```bash
find ~/work ~/sandbox -maxdepth 3 -name .git -type d | while read -r g; do
  d=$(dirname "$g"); git -C "$d" remote -v | grep -q . || echo "NO REMOTE: $d"
done
```

## How the session starts

There is no display manager. Login is a plain `getty` on tty1, and `~/.zprofile`
execs `start-hyprland` when it sees a login shell on `/dev/tty1` with no `DISPLAY`.
Hyprland is 0.56.1; Quickshell is 0.3.0 (as of 2026-08-21).

Both are pre-1.0-stability projects whose APIs break between releases, and the
shell, lock screen and wallpaper all die together if they do. After any
`pacman -Syu` that bumps either package, run `rice-doctor` **before logging
out** — it restarts the shell and greps the new instance's log for errors. If
it fails, the previous package versions are still in `/var/cache/pacman/pkg/`
(`sudo pacman -U <cached .pkg.tar.zst>`), and the fallback locker (hyprlock)
keeps the machine lockable meanwhile.

The login shell is zsh. `~/.bash_profile` and `~/.bashrc` are deliberately left in
place and working, so `chsh -s /usr/bin/bash` is a complete escape hatch if the zsh
path ever breaks. Machine and work environment (`AWS_REGION`, `OLLAMA_HOST`,
`PGHOST`) lives in `~/.config/zsh/local.zsh`, gitignored and sourced by `.zshrc`.

**Hyprland's active config is `hyprland.lua`, not `hyprland.conf`.** Binds show
`dispatcher: __lua`, and `hyprctl dispatch` calls take the `hl.dsp.foo(...)` form
there rather than the classic keywords.

`hyprland.conf` is not dead weight and not a historical copy. Hyprland reads it
whenever `hyprland.lua` is absent, and its only job is to answer one question:
does the compositor itself still start? Move the Lua config aside from a TTY
(`mv ~/.config/hypr/hyprland.lua ~/.config/hypr/hyprland.lua.off` — it is a stow
symlink, so this moves the link and `stow -R hyprland` puts it back) and log in
again. If a bare session comes up, the fault is in the Lua config or the shell,
not in Hyprland or the GPU. Keep it minimal; do not mirror the Lua config into it.

Recovery itself is not a rescue desktop. It is a TTY, the network, and Claude Code
in this repo: see [docs/RECOVERY.md](docs/RECOVERY.md).

## Shutting down without holding the power button

Every hard power-off costs an ext4 journal recovery and whatever was in flight, so
it is worth knowing the three levels.

**Machine responds** — `systemctl poweroff`, or just tap the power button.
`/etc/systemd/logind.conf` is empty, so systemd defaults apply, and the relevant one
is `HandlePowerKey=poweroff`: a short press is already a clean shutdown. The long
press is a firmware force-off that bypasses the OS entirely and is what causes the
recovery on the next boot. (The desktop's power menu is SUPER+ESC in the shell;
its SHUT DOWN asks first with a red confirm line — the old waybar power button
was removed for being a single unconfirmed click bound to `shutdown now`.)

**Session wedged, kernel alive** — Ctrl+Alt+F2, log in, `systemctl poweroff`. If a
TTY appears at all, the kernel is healthy and the disk is fine, so never hold the
power button in this state. This is also the path for the hyprlock-after-suspend bug
below.

**Fully hung** — this is what `kernel.sysrq=1` in `/etc/sysctl.d/99-sysrq.conf`
exists for. Hold Alt and SysRq (the PrtSc key) and tap, a second apart:

```
S   sync — flush pending writes
U   remount all filesystems read-only
B   reboot now
```

`S` and `U` are the whole point: they are the difference between a clean next boot
and `recovering journal` / `Clearing orphaned inode`. Test the key combination while
things work — `Alt+SysRq+H` prints a help line visible in `dmesg | tail`. If nothing
appears, the F-row is in media mode and `Fn` is needed too, which is much better to
discover now than during a hang.

Caveat for the failed-resume case specifically: if the kernel never came back from
s2idle, the keyboard input path is likely down too and SysRq will not respond. Try it
anyway — it costs two seconds — but holding the power button is then genuinely the
only option, and the journal recovery is unavoidable rather than a mistake.

## Services

Enabled at the system level:

```
NetworkManager  bluetooth  docker
sing-box  panel-od-off  power-profiles-daemon  battery-charge-limit
nvidia-suspend  nvidia-resume  nvidia-hibernate
```

Enabled for the user:

```
hyprpolkitagent  hyprsunset  wireplumber  pipewire-pulse
```

`ollama.service` is installed with a drop-in (`OLLAMA_HOST=0.0.0.0:11434`,
`OLLAMA_MODELS=/home/ollama-models`, `ProtectHome=false`) but is **not** enabled;
it gets started by hand when wanted. The models live outside `$HOME` at
`/home/ollama-models`, which is why the drop-in has to turn `ProtectHome` off.

## The battery charge limit

The limit is `battery-charge-limit.service`, which writes `80` to
`/sys/class/power_supply/BAT0/charge_control_end_threshold` at boot. It has to be a
unit rather than a value set once, because `asus_wmi` does not persist the threshold
across a reboot.

Only the end threshold exists on this laptop. There is no
`charge_control_start_threshold` node, so a start threshold is silently inert — TLP's
`START_CHARGE_THRESH_BAT0=75` never did anything at all.

**Why TLP is gone.** TLP used to own the limit. It was removed on 2026-08-20, after
the limit stopped working without any warning and the battery reached 87% on AC. The
cause is that `power-profiles-daemon.service` ships

```
Conflicts=tuned.service tlp.service auto-cpufreq.service system76-power.service
```

and the shell binds `PowerProfiles` (`SysState.qml`, `DetailsMenu.qml`), which
D-Bus-activates ppd at login even though the unit is not enabled. systemd then killed
TLP mid-init, after `Applying power save settings` and before
`Setting battery charge thresholds`. Every boot since the shell landed had no charge
limit. The journal shows it plainly — a boot with the limit applied logs both lines
and `Finished`, a broken one logs the first line and `killed, status=15/TERM`.

The two daemons do genuinely overlap on CPU scaling and `platform_profile`, so the
`Conflicts=` is not a packaging mistake. But it takes TLP down wholesale, including
the charge threshold, which ppd does not touch. Moving the threshold into its own
unit ends the argument: ppd keeps the CPU and platform-profile knobs, which is what
the shell's POWER MODE tile talks to, and the limit no longer rides on a daemon that
something else is entitled to shoot.

Nothing was lost with TLP. The governor, energy-performance-preference and
platform-profile settings in `tlp.conf` are ppd's job and ppd was already doing them,
and `tlp.d/99-nvme.conf` existed only to cancel TLP's own defaults — see the next
section.

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

**Ruled out, do not re-chase:** suspend/resume is not the trigger *for these
pre-fix crashes* (one came 46 minutes into a boot with no suspend at all), and the
kernel is not either (the first unclean shutdown predates the 7.0.11 → 7.1.5
upgrade). This is also distinct from the hyprlock-goes-deaf bug below, which still
lets you reach a TTY.

Read that first clause narrowly. It means suspend did not explain the crashes
described here; it is not a reason to skip suspend when investigating the separate,
undiagnosed resume failure in the next section.

**The fix** was `/etc/tlp.d/99-nvme.conf` plus the kernel command line. Since TLP was
removed on 2026-08-20 only the kernel command line remains, carried in `system/`, and
it is enough on its own. `RUNTIME_PM_ON_BAT` and `PCIE_ASPM_ON_BAT` were TLP settings
and that file existed only to cancel TLP's own aggressive defaults; with TLP gone the
kernel defaults are already what it was asking for —
`/sys/class/nvme/nvme0/device/power/control` reads `on` and
`/sys/module/pcie_aspm/parameters/policy` reads `default`. Nothing else on the system
writes either knob, power-profiles-daemon included. The metric for whether it is
working is the power cycle count, not the absence of crashes:

```bash
sudo smartctl -a /dev/nvme0n1 | grep -i "power cycles"
```

Baseline was 214,757 on 2026-08-14. After hours on battery it should climb by single
digits. If it still races upward, something is driving D3cold again — check the two
sysfs values named above before looking anywhere else.

**Measured 2026-08-17 09:12 — the fix works.** The count reads 214,762, so five
cycles in roughly 62 hours: down from about 21 an hour to about 0.08, a factor of
260. Five is also close to the number of times the machine was actually booted or
suspended over that window, which is what a healthy drive looks like — it powers
down when told to and not otherwise.

Still outstanding: check whether WD has released SN350 firmware newer than
`33006000`, since several controller hang bugs on this drive were fixed in firmware.
SMART reports `Firmware Updates (0x14): 2 Slots, no Reset required`, so a flash
would not need a cold reset, which makes it a low-risk thing to try.

## One failed resume, cause unknown

Kept separate from the section above on purpose, because the evidence does not
connect the two and an earlier draft of this document wrongly implied it did.

Counting every suspend cycle in the retained journal, 2026-08-13 to 2026-08-17:

```
Aug 13 09:59:33  ->  exit 10:15:16      ok
Aug 13 16:52:44  ->  exit 17:18:32      ok
Aug 14 09:58:56  ->  exit 09:59:18      ok
Aug 14 10:02:31  ->  exit 10:22:42      ok
Aug 14 17:40:50  ->  exit 18:08:09      ok
Aug 15 21:54:54  ->  exit 03:23:31      ok    5.5 hours suspended
Aug 16 18:11:09  ->  never returned     FAILED
Aug 17 04:07:12  ->  exit 04:19:39      ok
```

Seven of eight, including one 5½-hour suspend and one *after* the failure. Count
suspends, not boots — an earlier version of this document said "one bad boot in six"
and made a roughly 12% per-suspend failure rate sound like a per-boot one.

The failure itself is unremarkable up to the moment it stops. Wifi came down,
`nvidia-suspend` ran and finished, `systemd-sleep` started, the kernel logged
`PM: suspend entry (s2idle)` at 18:11:09 — and then nothing. No `PM: suspend exit`,
no shutdown record, and the next boot 7½ minutes later ran ext4 journal recovery on
both partitions. No low-battery events that day, so a flat battery is ruled out.

**What is not known is why.** There is no evidence tying this to the NVMe. The
pre-fix freezes had a distinct signature — machine live, drive LED flashing, during
normal use — and this has none of it, because nothing can log once the kernel is
down in s2idle. Failed s2idle resumes are also common on AMD laptops for GPU and
firmware reasons unrelated to storage. One unexplained resume failure in eight is
close to the background rate for this hardware and is not yet a diagnosed bug.

If it happens again, **look at the front-panel drive LED while it is stuck**. That
single observation splits the diagnosis: flashing means storage and the section
above applies, dark means the GPU or firmware path and the NVMe work is irrelevant.
Note also whether it was on AC or battery, and how long it had been suspended. Two
data points with the LED settle it; one without is a coin flip.

## Other quirks that come with this machine

**The lock screen goes deaf after suspend.** The primary locker is the
Quickshell surface now (Lock.qml); whether it shares this bug is untested —
what follows was reproduced with hyprlock, which remains the fallback locker,
and `fixlock` still targets hyprlock. Locking and then suspending leaves
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
for `api.anthropic.com`. The same stalls appear across boots going back to
2026-08-15 (30 of them, one at 4m8s), so this is long-standing and unrelated to
any wifi change.

`systemctl is-active sing-box` is useless for diagnosing it — the service reports
active while the tunnel passes no traffic. Run `netcheck.sh` instead: it tests the
link, then pings the gateway and 1.1.1.1 with `-I` on the wifi interface to
bypass `tun0`, then
makes a real HTTPS request through the tunnel. Layers 0-2 passing with layer 3
failing means `sudo systemctl restart sing-box`, not a reboot.

**When it really is the network, `wifi-doctor` says which layer.** `netcheck.sh`
answers one question — link or tunnel — and answers it well. `wifi-doctor` covers
the six rungs below the tunnel: rfkill and driver, NetworkManager and its
supplicant running,
association and signal quality, the DHCP lease and default route, the gateway, and
the internet. It stops at the first broken rung and prints the fix for that rung
only, and like `netcheck.sh` it pings with `-I` on the wifi interface so a dead
`tun0` cannot
masquerade as dead wifi. When all six pass it hands off to `netcheck.sh`.

`wifi-doctor --log` is the half that matters after the fact, since a reboot erases
the live state that would have explained the failure. It reads a boot's journal and
prints the NetworkManager connectivity timeline with a duration against each state,
plus a count of known failure signatures — DHCP getting no answer, a rejected PSK,
beacon loss, a driver firmware reset, AP roams, NTP timeouts. `wifi-doctor --log -1`
reads the boot before the last reboot, which is the only way to diagnose anything
that was already "fixed" by rebooting.

**Wifi that is associated but has no internet is the router, not the laptop.** On
2026-08-21 wifi appeared dead for 1h32m and was rebooted away. `wlan0` never
deauthenticated, never roamed and held `10.0.0.234` throughout; NetworkManager had
simply dropped from `CONNECTED_GLOBAL` to `CONNECTED_SITE` at 10:29:08, with
timesyncd already timing out against four NTP servers from 10:25:57. That state
means the LAN answers and the internet does not, so it is the router's WAN or the
ISP and no local command reaches it. `nmcli general` reports it in one line;
`CONNECTED_SITE` or `limited` means power-cycle the router rather than the laptop.
A DHCP failure the same night at 03:40:27 — `no lease` after a roam, then
`ip-config-unavailable` — points at the same router.

**sing-box loses a race with the uplink on every boot.** Journal signature, unchanged
across every boot checked between 2026-08-15 and 2026-08-17:

```
Finished Network Manager Wait Online.        <- returns in the same second
Started sing-box service.
sing-box: ERROR network: missing default interface
(5s later) NetworkManager: dhcp4 (wlan0): new lease, address=192.168.1.4
```

sing-box builds its `auto_route` / `auto_detect_interface` tun0 state against a
nonexistent uplink. When it does not rebuild that state, every dial fails with `no
route to internet`, and because DNS uses a `detour: proxy` server, name resolution
dies with it, and only a service restart recovers it.

**It does not always end that way.** The 2026-08-17 09:01 boot produced the error on
schedule — wait-online started and finished in the same second at 09:01:49, sing-box
started and logged `missing default interface` in that same second, and the DHCP
lease arrived 12 seconds later at 09:02:01 — and yet the tunnel came up fine, with
`netcheck.sh` passing all four layers minutes afterwards. So the accurate statement
is that the error fires on every boot and the tunnel sometimes recovers on its own.
That matches the history of intermittent stalls rather than constant failure. It is
a reliability problem, not a guaranteed daily outage, and `netcheck.sh` rather than
the presence of the log line is what says whether it matters on a given day.

`After=network-online.target` buys nothing here, because wait-online waits for
NetworkManager *startup-complete*, which NM can declare before wifi associates.
As of 2026-08-17 the only drop-in actually present is
`sing-box.service.d/override.conf` containing `Wants=network-online.target`, which
for the same reason does not fix it. **Treat this as still open.** A working fix
needs wait-online overridden to `nm-online -q --timeout=60` and an `ExecStartPre`
that polls `ip route show default`.

**Rule-set caching is on, contrary to what an earlier version of this document
said.** `/etc/sing-box/config.json` does have an `experimental.cache_file` block,
verified 2026-08-17:

```
experimental.cache_file = { "path": "cache.db", "store_rdrc": true }
```

The concern it removes is worth recording anyway, because it is the failure to look
for if the block is ever lost: without caching, the remote `geoip-cn` and
`geosite-cn` rule sets are re-downloaded at every start, and those downloads run
straight into the boot race above. When they fail the rule sets are simply absent,
and all China-destined traffic silently routes through the proxy instead of direct —
slow, and it presents as a proxy problem rather than a config one.

**The eduroam profile is PEAP/MSCHAPv2 and has not been used recently.** If it will
not associate on campus, set `802-1x.ca-cert` and `802-1x.domain-suffix-match` on
that profile.

## What in this repo is hardware-specific

Safe anywhere — the stow packages, with the one `.zprofile` exception in the
table. Configs for Hyprland, the Quickshell shell, kitty, zsh, starship, and
the scripts in `local-bin`. Worst case a keybind refers to hardware that is
not there.

Tied to this laptop — most of `system/`, plus one line of `.zprofile`:

| File | Tied to |
|---|---|
| the grub NVMe parameter | the WD SN350 controller specifically |
| `systemd/system/panel-od-off.service` | an ASUS `asus-nb-wmi` sysfs path |
| `systemd/system/battery-charge-limit.service` | the ASUS `asus_wmi` charge-threshold node |
| `wireplumber` soft-mixer drop-in | the ALC285 node name |
| `.zprofile` `AQ_DRM_DEVICES` | the AMD iGPU's PCI address, `/dev/dri/by-path/pci-0000:04:00.0-card`; resolves to nothing and is skipped on other hardware |
| `rootfstype=ext4` in the grub cmdline | this machine's root filesystem |

`system/install.sh` checks the DMI product name and refuses to run on non-G14
hardware unless given `--force`, for exactly these reasons.
