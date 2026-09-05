# Session transcript — UPower stale state investigation

Recorded 2026-08-25, Claude Code session `b9083c9c`. Tool calls and their output are
omitted; only the questions and answers are kept. The findings are summarised
separately in `2026-08-25-power-management.md`.

---

## Q

details menu shows power plugged in even when not plugged in, why? do not write code

---

## A

**Root cause: stale `state` on `UPower.displayDevice` in the running shell — startup race, never re-emitted.**

Evidence:

- Hardware truth now: `AC0 online: no`, `DisplayDevice State = 2 (Discharging)`, daemon `OnBattery = true`, 42%.
- Deck shows chip `PLUGGED` + `PLUGGED IN · LIMIT 80%` (screenshotted deck live).
- Both come from `SysState.onBattery` (`DetailsMenu.qml:956`, `SysState.qml:37`), which reads `battery.state`, not `UPower.onBattery`.
- Fresh probe instance of quickshell: `t=0` → `ready=false state=0 pct=0`; `t=2.5s` → `ready=true state=2 pct=0.43`. So logic and enum are correct.
- Running instance (pid 2551, started 10:47:00 — upower daemon touched AC0 at 10:47:02, 2s later): its percentage IS live (bar read 43 then 42, tracking dbus exactly), so `ready` true and PropertiesChanged flowing. Only `state` is wrong.

Mechanism: shell started before UPower populated DisplayDevice, latched `State = Unknown (0)`. `State` has not *changed* since boot (unplugged whole session), so UPower never emits a PropertiesChanged for it — `Percentage`/`TimeToEmpty` change constantly and do update. `state = 0` matches neither `Charging` nor `Discharging/PendingDischarge/Empty`, so `charging=false`, `onBattery=false` → the "else" branch, which reads PLUGGED. The `UPower.onBattery` fallback (correct, `true`) is skipped because `ready` is true.

Second symptom, same cause: `syncNature()` (`SysState.qml:395`) set profile from `onBattery=false`, so `powerprofilesctl get` = `balanced` on battery instead of `power-saver`.

Not a wiring/hardware issue; restarting `qs` would clear it until the next boot race.

Fix direction when you want it: don't treat `displayDevice.state` as sole truth — cross-check `UPower.onBattery` or `line_power_AC0.online`, or re-read state when `ready` flips true.

Side effects of diagnosis: opened and closed the deck via `qs ipc call details toggle/close`, ran a throwaway probe instance (`scratchpad/probe.qml`), took screenshots. Nothing in the repo touched.

---

## Q

who manages battery and performance? how is that setup, how is battery life on the computer? I want to understand everything, please explain to me

---

## A

## Who manages what

Five layers, one policy daemon.

| Layer | What it owns | Notes |
|---|---|---|
| `asus_wmi` firmware node | 80% charge cap, `platform_profile`, panel overdrive, fan curve | written by units, not persisted across reboot |
| `amd-pstate-epp` (kernel, `status=active`) | CPU freq + energy-performance-preference | driver, no policy of its own |
| `power-profiles-daemon` 0.30 | the only policy daemon: governor, EPP, `platform_profile` | **unit disabled**, runs only because quickshell binds its D-Bus name |
| `upower` | reporting only — percentage, rate, time-left | no control |
| nvidia driver, `NVreg_DynamicPowerManagement=0x02` | dGPU runtime D3 (fine-grained) | display runs on AMD iGPU (`card1 = amdgpu`), dGPU idles off |
| quickshell `SysState.qml` | auto-picks ppd profile from AC state; deck POWER panel = manual override | this is the one broken piece, see below |

No TLP, no auto-cpufreq, no thermald, no asusctl, no cpupower. Removed 2026-08-20 — TLP got killed mid-init by ppd's `Conflicts=`, silently losing the charge limit (MACHINE.md:280).

Two oneshot units at boot: `battery-charge-limit.service` (writes 80 to `charge_control_end_threshold`), `panel-od-off.service` (overdrive off). Both enabled. Only end threshold exists in sysfs; upower reporting `charge-start-threshold: 75%` is firmware noise, no node backs it.

## Profile mapping (measured live, then restored to balanced)

```
power-saver  gov=powersave    epp=power        platform=quiet        max 3.20 GHz
balanced     gov=powersave    epp=balance_power platform=balanced    max 4.47 GHz
performance  gov=performance  epp=performance  platform=performance  max 4.47 GHz
```

power-saver is the only one that hard-caps clocks (−28%). No app holds active.

## Battery, real numbers

Health: 58.98 Wh full vs 75.998 Wh design = **77.6%**, ~2 years of wear. Cap at 80% leaves **47.2 Wh usable**.

One week of upower samples (Aug 18–25, 1558 discharge points):

```
p10  7.5W   p25 10.0W   p50 14.0W   p75 15.1W   p90 18.4W   p99 26.2W   max 50.6W
mean 13.2W
```

Runtime from a full (80%) charge:

```
light idle, browser only   7.5-10W   4.7-6.3 h
typical mixed              13-14W    3.4-3.6 h
heavy / builds             18-26W    1.8-2.6 h
gaming, dGPU loaded        50W       ~1.0 h
```

Charging 41 W average, 0→80% ≈ 1.2 h nominal (real ~1.4 h with taper).

Suspend: measured this session — 12:51:20 → 15:48:33 s2idle cost ≈1.4 Wh net = **~0.5 W**, roughly 1%/h, ~4 days standby. Normal-good for s2idle; no S3 on this platform.

## What is already right

- dGPU genuinely asleep: 7,774 s suspended vs 107 s active over 2.19 h awake — 1.4% duty. `nvidia-smi` reading 16.7 W just now is my own probe waking it.
- Panel forced to 60 Hz (`hyprland.conf:20`), panel OD off — both real savers vs the 144 Hz option.
- zram-only swap, no disk swap thrash.
- ppd/TLP conflict resolved by moving the charge cap into its own unit.

## What costs you battery right now

1. **Profile stuck on `balanced` while on battery.** The auto-switch in `SysState.qml:395` (`syncNature`) only fires on `onOnBatteryChanged`, and `onBattery` is false because of the stale `displayDevice.state` bug from earlier. So the machine never drops to power-saver unplugged — you lose the 3.2 GHz cap and `epp=power`. Worth maybe 1.5–3 W under load, i.e. tens of minutes.
2. **ppd is `disabled` as a unit.** It runs by D-Bus activation from the shell only. Kill or fail the shell and CPU policy silently reverts to kernel defaults with nothing managing `platform_profile`.
3. **docker.service active** at idle for nothing most of the time; containerd idles ~0.3–0.8 W.
4. Brightness at 50% (31226/62451) — the panel is the single biggest lever left, roughly 1–3 W across the range.
5. Firefox + Discord idle at ~5% and ~1.4% CPU; that is most of the gap between the 7.5 W p10 and the 14 W median.

Current state as I write: 37%, 12.0 W, discharging, `balanced`, Tctl 46.9 °C, fans 2400/2500 RPM.

Only change I made: cycled ppd profiles to measure the mapping, ended back on `balanced` where I found it.

---

## Q

is the setup normal or is it hacky, what is the correct approach to manage battery?

---

## A

## Verdict: mostly normal, two hacky bits

**Normal, in fact current best practice:**

- ppd alone on `amd-pstate-epp`. This is what Fedora/GNOME/KDE ship by default and what upstream recommends on modern AMD. TLP is the *older* approach and actively fights ppd — you already learned that the hard way.
- One-shot unit writing `charge_control_end_threshold`. Straight out of the Arch wiki; `asus_wmi` does not persist thresholds, so a boot-time write is the documented answer, not a hack. Same for `panel-od-off`.
- `NVreg_DynamicPowerManagement=0x02` + iGPU-driven display. Textbook Optimus setup.
- No thermald (Intel-only anyway), no cpupower, no manual governor pinning. Correct — leaving `amd-pstate-epp` to ppd is the sane layering.

**Hacky:**

1. **ppd unit is `disabled`, running only by D-Bus activation from quickshell.** This is the real smell. Your CPU policy daemon starts as a side effect of a QML binding. No shell, no CPU management — and nothing tells you. Should be `systemctl enable power-profiles-daemon`.
2. **AC-to-profile switching lives in the compositor shell** (`SysState.qml:395`). GNOME and KDE do the same thing in *their* shells, so the idea is standard; the fragility is that yours derives AC state from `displayDevice.state`, which is exactly what broke today. Symptom: unplugged for 5 hours, still on `balanced`.

Everything else is fine. `asusctl` (AUR only, not in repos) would give persistent thresholds, fan curves and `ppt_pl1_spl`/`ppt_pl2_sppt` power-limit control in one daemon — but it overlaps ppd on `platform_profile` and would reopen the conflict you just closed. Not worth it for a threshold you already handle in six lines.

## Correct approach, ordered by value

1. `systemctl enable power-profiles-daemon` — remove the accidental dependency on the shell.
2. Make AC detection robust: read `UPower.onBattery` or `/sys/class/power_supply/AC0/online`, not `displayDevice.state` alone. Or move the switch out of QML entirely into a udev rule on `SUBSYSTEM=="power_supply"` calling `powerprofilesctl set`, and let the deck be display-only. udev fires on the actual AC transition, has no startup race, and survives the shell dying.
3. Keep the charge cap. 77.6% health at 80% cap is the right trade; drop it to 100% by hand the day before travel.
4. Leave the rest alone. dGPU D3, 60 Hz, panel OD, zram are all already correct.
5. Do not reinstall TLP. The overlap is real and ppd already does its job.

The only actual defect in the whole stack is the stale `state` read, and it costs you one profile step — 1.5–3 W — every time you unplug.

---

## Q

diff asusctl and power-profiles-daemon

---

## A

## Not substitutes — different layers, one overlap

| | power-profiles-daemon 0.30 | asusctl (`asusd`) |
|---|---|---|
| Origin | freedesktop, C | ASUS Linux project, Rust |
| Availability | `extra/power-profiles-daemon` — installed | **AUR only** (not in `extra` as of your Aug 16 db) |
| Scope | generic laptop power policy | ASUS-specific hardware knobs |
| CPU governor / EPP | **yes** — this is its core job | no, does not touch cpufreq |
| `platform_profile` | yes | yes (via `throttle_thermal_policy`) ← **the overlap** |
| Fan curves | no | yes, per-profile custom curves (`asus_custom_fan_curve` — your kernel exposes it, `sensors` shows the chip) |
| CPU power limits `ppt_pl1_spl`/`ppt_pl2_sppt` | no | yes |
| Charge threshold | no | yes, persistent — reapplies itself |
| Panel overdrive, mini-LED, keyboard Aura RGB, AniMe matrix, POST sound | no | yes |
| dGPU mode switching | no | no — separate `supergfxctl` |
| App-driven holds ("Steam wants performance for 30s") | **yes**, D-Bus holds API | no |
| Desktop integration | GNOME/KDE/quickshell talk to it natively | own D-Bus name, own GUI (`rog-control-center`) |
| Profiles | exactly 3: power-saver / balanced / performance | profiles + independent knobs |

## What that means concretely

`ppd` is a *policy* daemon: it maps three names onto `scaling_governor`, `energy_performance_preference` and `platform_profile`, and exposes a stable API anything can call. You measured it doing exactly that.

`asusd` is a *hardware* daemon: it drives the ASUS WMI nodes the kernel exposes and nothing else. It never sets a governor or EPP. If you installed it today and stopped ppd, your CPU would fall back to whatever `amd-pstate-epp` defaults to, unmanaged.

So installing asusctl does **not** replace ppd. The realistic setup is both, with asusd handling fans/thresholds/LEDs and ppd keeping the CPU — and they must agree on who writes `platform_profile`. Recent asusd versions can follow ppd's profile changes instead of fighting it; ppd's `Conflicts=` line does not list asusd, unlike tlp. I have not verified the current asusctl release's integration behavior on this machine — that's the one thing to check before installing.

## For your machine specifically

What asusctl would actually buy you:

- Persistent charge limit → deletes `battery-charge-limit.service`. Six lines replaced by a Rust daemon and an AUR dependency. Poor trade.
- Fan curve control → real gain if 2400/2500 RPM at 46 °C idle annoys you. ppd cannot do this at all.
- `ppt_pl1_spl` / `ppt_pl2_sppt` tuning → could cut sustained draw more precisely than the 3.2 GHz cap power-saver gives you. Both nodes read `5` right now, which is almost certainly not watts; I did not chase what the scale means.
- Aura keyboard lighting, panel OD → you already handle OD with a one-shot unit.

What it would cost: an AUR package tracking kernel `asus_wmi` changes, plus a second writer on `platform_profile` — the exact class of double-ownership that silently ate your charge limit under TLP.

Recommendation stands: keep ppd as the sole policy daemon. Add asusctl only if you specifically want fan curves or PPT tuning, and if you do, verify it defers to ppd on `platform_profile` before trusting it.

---

## Q

so what does ppd do right now

---

## A

**Right now, on battery at 30%, AC0 offline:**

```
ActiveProfile:  balanced          (unchanged since boot 10:47, except my probe)
governor:       powersave         all 16 cores
EPP:            balance_power     all 16 cores
platform_profile: balanced
holds:          none
PerformanceDegraded: ""           (no thermal/firmware throttle flag)
BatteryAware:   true
Actions:        trickle_charge
```

So concretely it is doing three things: writing `powersave` to every core's governor, writing `balance_power` to every core's EPP, and writing `balanced` to `/sys/firmware/acpi/platform_profile`. That is the entire footprint. It set those at 10:47 and has not touched them since — the journal for this boot is two lines, start and started.

Worth separating from the earlier finding: **`BatteryAware: true` means ppd itself knows you are on battery.** It reads UPower directly and correctly. That is why EPP is `balance_power` rather than `balance_performance` — inside the `balanced` profile, ppd already picked the battery-side EPP for you.

What it does *not* do is switch the profile itself. `balanced` → `power-saver` is not ppd's job by design; ppd waits for a client to ask. On this machine the only client that would ask is quickshell's `syncNature`, and that is the piece reading stale state. So you get ppd's battery-side EPP but not the 3.2 GHz cap and `epp=power` that `power-saver` would apply.

Also idle: `Actions: trickle_charge` is ppd's only background behavior, and it applies to USB devices' charge type, not the laptop battery. Nothing else of ppd is running.

---

## Q

what is governor epp, cores etc

---

## A

## Cores

`AMD Ryzen 7 5800HS`: **8 physical cores, 2 threads each = 16 logical CPUs**. Linux exposes one cpufreq policy directory per logical CPU (`/sys/devices/system/cpu/cpu0..cpu15/cpufreq/`), so any setting has to be written 16 times — that is why I said "all 16 cores" when reading EPP back. Sibling threads share one physical core and therefore one clock; writing different values to a pair is meaningless.

Live right now:

```
1928 1103 1884 1103 1714 1714 1716 1103 2146 1103 1775 1103 2146 1103 1716 1716 MHz
```

The repeated 1103 is the floor, not idle-idle. Range on this part: 403 MHz hardware minimum, 4465 MHz maximum, but `scaling_min_freq` is set to **1102866** = `amd_pstate_lowest_nonlinear_freq`. Below that the chip burns more energy per unit work than it saves, so the driver refuses to go there under load — the hardware still drops lower on its own when fully idle.

## Governor

The kernel's frequency-selection policy. Historically: `ondemand`, `conservative`, `schedutil` — algorithms that sampled load and stepped clocks up and down.

On `amd-pstate-epp` only two exist:

```
performance powersave
```

Both names are misleading here. In EPP mode the kernel is **not** picking frequencies. `powersave` means "hand the decision to the CPU's own hardware governor (CPPC autonomous mode) within the allowed range". `performance` means "pin the requested performance to maximum". So `powersave` is the normal, correct, full-speed-capable setting — your cores just hit 2.1 GHz under it. It is not a slow mode.

## EPP — energy performance preference

A hint, 0–255, handed to the silicon's own governor telling it how eagerly to ramp up when work arrives. The hardware re-decides roughly every millisecond, far faster than any kernel loop could.

```
performance  balance_performance  balance_power  power   (+ default, custom)
0 ───────────────────────────────────────────────────► 255
eager ramp, high idle draw              lazy ramp, low draw
```

Yours is `balance_power` — biased toward power, still allowed to reach 4465 MHz when demand is sustained. It just waits longer before deciding demand is real.

Related node: `amd_pstate_highest_perf=166`. CPPC works in abstract "performance units" 0–255, not MHz; 166 is what this silicon maxes at. `prefcore_ranking=166` marks cpu0's core as a preferred (best-binning) core the scheduler favors for bursty single-thread work.

## The stack, top to bottom

```
platform_profile  (firmware / asus_wmi)  → fan curve + SoC power limits (PPT)
        ▲ ppd writes this
governor          (kernel)               → who decides: hardware or pinned max
        ▲ ppd writes this, 16×
EPP               (kernel → CPPC)        → how eagerly hardware ramps
        ▲ ppd writes this, 16×
CPPC              (silicon, ~1 ms loop)  → actual MHz, per core
        ▲ nobody writes this
thermals / PPT    (firmware)             → hard ceiling regardless of the above
```

ppd only touches the three marked layers. Everything below is out of software's hands.

This is why the three profiles differ the way you measured:

```
power-saver  gov=powersave    epp=power             platform=quiet        max 3.20 GHz
balanced     gov=powersave    epp=balance_power     platform=balanced     max 4.47 GHz
performance  gov=performance  epp=performance       platform=performance  max 4.47 GHz
```

`power-saver` is the only one that lowers the actual ceiling, and that ceiling comes from the firmware side (`platform_profile=quiet`), not from the governor. `performance` does not raise the ceiling at all — it just stops the chip from ever waiting before using it.

---

## Q

i'm confused if ppd writes the epp didn't you say that epp is written every millisecond by the hardware? so wouldn't it get overwritten?

---

## A

Bad phrasing on my part — the hardware doesn't write EPP, it *reads* it.

EPP is an **input**, frequency is the **output**.

```
software writes ──► EPP byte in MSR_AMD_CPPC_REQ ──► hardware reads it every ~1 ms
                    (also min_perf, max_perf,          along with load, temp, PPT
                     desired_perf fields)              ──► picks this millisecond's MHz
```

The ~1 ms loop I described is the hardware choosing a **frequency**. It consults EPP as one of its inputs each time. It never writes back to that field. Nothing in silicon modifies EPP.

So the MSR field just sits there holding whatever the last software write put in it. ppd wrote `balance_power` at boot; it still reads `balance_power` five hours later. That persistence is the proof — if anything were overwriting it, a value set once at 10:47 would not survive.

The only things that ever change it:

- ppd on a profile switch (what you saw: `power` / `balance_power` / `performance` for the three profiles)
- the `amd-pstate-epp` driver itself when the **governor** changes — switching to the `performance` governor forces EPP to `performance` and restores the previous value when you switch back. That is why `performance` profile showed both `gov=performance` and `epp=performance`; ppd set the governor, the driver forced the EPP.
- you, writing to the sysfs file by hand
- suspend/resume, where the driver restores its cached value

The analogy: EPP is the position of a dial. The hardware reads the dial a thousand times a second to decide how hard to run. Reading a dial does not turn it.

---

## Q

what is amd-pstate-epp, do i have that, do i need that?

---

## A

**What it is**

`amd-pstate-epp` is the cpufreq *driver* — the kernel module that talks to the CPU's frequency hardware. It is the ACPI CPPC path: instead of the kernel picking a frequency from a table and writing it, the kernel writes a performance *request* (min, max, desired, EPP) into `MSR_AMD_CPPC_REQ` and the silicon picks the actual operating point itself.

Three generations of this on AMD:

```
acpi-cpufreq       legacy. Kernel picks from ~3 coarse P-states via ACPI tables.
                   Governors ondemand/schedutil. Slow to react, coarse steps.
amd-pstate         "passive" mode. CPPC hardware, but a kernel governor
                   (schedutil) still drives it. EPP unused.
amd-pstate-epp     "active" mode. Hardware autonomously picks frequency;
                   kernel only sets the bounds and the EPP bias. ← yours
```

Active mode reacts in microseconds and uses the full continuous frequency range (403–4465 MHz here) rather than a handful of P-states.

**Do you have it**

Yes, and correctly configured:

```
scaling_driver:            amd-pstate-epp
amd_pstate/status:         active
amd_pstate/prefcore:       enabled
kernel:                    7.1.5-arch1-2
cpuinfo flag:              cppc          (firmware exposes CPPC)
kernel cmdline:            no amd_pstate= parameter — this is the built-in default
```

Nothing in your config enabled it. Modern kernels default to active mode on Zen 2+ where firmware reports CPPC, and yours does. `prefcore=enabled` additionally means the scheduler knows which physical cores bin highest (`prefcore_ranking=166` on cpu0) and steers bursty single-threaded work there.

**Do you need it**

Yes — and more to the point, you already depend on it. Two reasons specific to this machine:

1. **EPP only exists in this mode.** `energy_performance_preference` is a file that `amd-pstate-epp` creates. In passive mode or under `acpi-cpufreq` it is absent, and ppd loses two of its three levers — `powerprofilesctl list` would report a different `CpuDriver` and the profiles would collapse toward just `platform_profile` changes. Your measured difference between `balance_power` and `power` would simply not be available.

2. **Battery.** Hardware-autonomous scaling is where the idle-power win lives on Zen 3 mobile — the chip drops cores to the floor between keystrokes far faster than a kernel governor sampling every few milliseconds. Your p10 draw of 7.5 W depends on it.

Nothing to install, nothing to enable, no kernel parameter to add. The one thing worth knowing is what *not* to do: adding `amd_pstate=passive` or `initcall_blacklist=amd_pstate_init` to the cmdline, or forcing `acpi-cpufreq`, would silently break ppd's EPP control. Some older laptop-tuning guides still recommend exactly that. They predate active mode.

---

## Q

how to fix the bug, explained simply

---

## A

## The bug in one sentence

`onBattery` asks the battery "what are you doing?" — at boot the answer was `Unknown`, and since the answer never *changed* afterwards, nobody ever told the shell otherwise.

## Why it never self-corrected

`SysState.qml:37` reads:

```
onBattery = ready ? (state is Discharging/PendingDischarge/Empty) : UPower.onBattery
```

Boot sequence, what actually happened at 10:47:00:

1. UPower not up yet → `ready=false`, so it falls back to `UPower.onBattery`, which is also not up yet → **false**.
2. Two seconds later UPower appears. `ready` flips true, `state` is read as `Unknown (0)`. `Unknown` is not in the discharging list → **still false**.
3. The comment at line 400 expects `onOnBatteryChanged` to fix this "a moment later". But the value went false → false. **No change means no signal.** Nothing fires. It sits there for the rest of the boot.

And `state` never updates on its own, because UPower only announces *changes*. You have been discharging since before boot, so `state` genuinely never changed — no announcement, no correction. Meanwhile `percentage` changes constantly, which is why the number is live while the plug status is frozen. One property fresh, its neighbour stale, same object.

## The fix

Stop treating `ready` as "the answer is trustworthy". `Unknown` is not an answer. Make the fallback trigger on a meaningless *value*, not just on an unready device:

```
if state is Discharging, PendingDischarge, or Empty  → on battery
if state is Charging, FullyCharged, or PendingCharge → not on battery
otherwise (Unknown, or device not ready)            → use UPower.onBattery
```

That is the whole change, in `SysState.qml:37-41`. The existing comment's reasoning stays valid — `state` is still preferred when it says something real, which is what fixed the old "CHARGING while draining" bug. It just no longer lets `Unknown` outrank the daemon flag.

Two things follow for free:

- **The profile un-sticks.** Once `onBattery` becomes true, it *changes*, so `onOnBatteryChanged` finally fires, `syncNature()` runs, and ppd drops to `power-saver` — the 3.2 GHz cap and `epp=power` you have been missing all session.
- **The deck reads right.** Chip becomes `BATTERY`, sub-label becomes `2:54 LEFT · LIMIT 80%`.

## Worth adding, optional

A safety net for the same class of race: re-run `syncNature()` when `battery.ready` flips true, not only when `onBattery` changes. Costs one line and covers any future property that arrives late.

Want me to make the change?

---

## Q

if it flipped from false to false how did it change?

---

## A

It didn't change. That's exactly the bug.

Two different things are moving, and only one of them counts:

- **The binding re-evaluates.** When `ready` flipped false→true, QML recomputed the whole expression. It ran.
- **The result stayed false.** Before: false (fallback, UPower not up). After: false (`Unknown` isn't in the discharging list).

QML only emits `onOnBatteryChanged` when the *result* differs from the previous result. Recomputing and getting the same answer emits nothing. So the recompute happened, silently, and `syncNature()` was never called again.

The line 400 comment assumes the recompute will produce a *different* answer — "the signal corrects it a moment later". That assumption holds when the fallback and the real reading disagree. Here they agreed on the wrong answer, so there was nothing to correct with.

What the fix changes: at step 2, `state=Unknown` now routes to `UPower.onBattery`, which by then is **true**. So the recompute yields false→**true** — a real change — the signal fires, and `syncNature()` drops ppd to `power-saver`.

Short version: today the value is wrong *and* stable, which is the worst combination, because every mechanism that would repair it is triggered by instability.

---

## Q

give me the whole timeline so I can make sure this is the correct way to solve it, i don't want to introduce one-off fixes that just pollute the machine later down the line

---

## A

# The timeline

All timestamps from this boot's journal and the shell's own log.

```
10:46:55  systemd    Reached target Graphical Interface
10:46:59  wireplumber "Failed to get percentage from UPower:
                       org.freedesktop.DBus.Error.NameHasNoOwner"   ← UPower not running
10:47:00  systemd    qs -d launched
10:47:01.700  qs     Launching config: shell.qml
              ↓      SysState singleton constructs, binds Quickshell.Services.UPower
              ↓      that bind is a D-Bus call to a name with no owner
10:47:02  systemd    Starting Daemon for power management...     ← activated BY the shell
10:47:02  systemd    Starting Power Profiles daemon...           ← activated BY the shell
10:47:02  systemd    Started both
10:47:02  upower     AC0 enumerated, online=0  (last update to this device, ever)
```

Neither `upower.service` nor `power-profiles-daemon.service` is enabled. Both are `disabled`, and both got started at 10:47:02 because a QML binding in your shell touched their D-Bus names. The shell is the reason those daemons exist on this machine.

## What the property did

```
t=0      qs binds UPower.        ready=false   UPower.onBattery=false (default, unread)
                                 → onBattery = false     via the fallback branch
t≈2s     upower answers.         ready=true    state=Unknown(0)
                                 → onBattery = false     via the state branch
                                 → false → false: NO onOnBatteryChanged signal
                                 → syncNature() never re-runs
                                 → ppd left on balanced for the next 5 hours
t=2s..now  percentage/energy-rate/timeToEmpty stream in normally via
           PropertiesChanged. state never re-announced, because state never changed —
           you have been discharging since before boot.
```

My probe instance confirms the shape of the race: at `Component.onCompleted` it read `ready=false state=0 pct=0`, and 2.5 s later `ready=true state=2 pct=0.43`. Same window, but the probe was still evaluating when the correct values landed, so it caught them.

**Honest boundary on the evidence.** I cannot introspect the running instance's `state` directly — quickshell exposes no eval IPC. What is *proven*: `SysState.onBattery` is false while UPower reports discharging, and `percentage` is live (bar tracked 43→42 in lockstep with D-Bus). What is *inferred*: that the specific stale property is `state`. `ready` being false would also explain it, except then `hp` would be 1 and the bar would read 100%, which it does not. So `state` is the culprit with high confidence, not certainty.

## The bug classes, separated

This is the part that matters for your question. There are four distinct defects here, and the one-line ternary patch only addresses the first.

```
1. Unknown outranks the fallback     onBattery treats state=Unknown as "answered"
2. Change-only propagation           the self-correction fires on value change, and
                                     the wrong value equals the default value
3. Policy lives in the display layer  syncNature() is the only thing switching ppd
4. Daemons are D-Bus-activated by     upower and ppd exist only because the shell
   the UI process                     touched them; ordering is whatever qs does first
```

Class 3 is the expensive one. A display bug cost you real battery for five hours, and it can only do that because a QML file is the machine's power-management policy. Class 4 is why the race window exists at all — the consumer starts the producer, so the consumer is by construction first.

## Options, judged against those classes

| Fix | Kills | Leaves | Verdict |
|---|---|---|---|
| Ternary patch: `Unknown` falls back to `UPower.onBattery` | 1 | 2, 3, 4 | correct, minimal, but depends on `UPower.onBattery` being fresh — the very flag your own comment at `SysState.qml:33` says once read stale |
| Re-run `syncNature()` on `ready` change too | 2 | 1, 3, 4 | plaster over the signal gap, doesn't fix the wrong value |
| Poll AC state on a timer in QML | 1, 2 | 3, 4 | polls forever to paper over one boot second — this is the kind of thing you said you don't want |
| **udev rule on `power_supply`** calling `powerprofilesctl` | 2, 3, 4 | 1 (display only) | kernel-event driven, fires at coldplug so no boot race, works with the shell dead |
| **Enable `upower.service` + `power-profiles-daemon.service`** | 4 | — | one `systemctl enable`, removes the activation ordering entirely |

I verified the udev path is available: `/sys/class/power_supply/AC0` exposes `SUBSYSTEM=="power_supply"`, `ATTR{online}=="0"`, and udev coldplugs `add` for it at boot, so the rule applies once at startup and then on every plug transition.

## What I'd actually do

Three changes, each removing a class rather than patching an instance:

1. **`systemctl enable upower power-profiles-daemon`.** They are already running on every boot anyway — by accident, via your UI. Making that explicit costs nothing, documents reality, and closes the race window.
2. **Move the AC→profile rule to udev.** Policy stops living in a QML file. Survives the shell crashing, restarting, or being rewritten. This is the change that means a future display bug cannot cost you battery again.
3. **Then fix the ternary** — `Unknown` falls back — because the deck should still *display* the truth. But it is now cosmetic, which is the correct severity for a shell binding.

That leaves `SysState.qml` doing only what a shell should do: showing state, and offering a manual override. Which, notably, is exactly the split your MACHINE.md already argues for in "The battery charge limit" — the limit moved out of TLP into its own unit for the same reason.

Say the word and I'll implement any subset. My recommendation is all three, in that order.

---

## Q

what is upower?

---

## A

**UPower is the reporting layer.** It reads battery/power hardware and publishes it on system D-Bus so every other program doesn't have to parse sysfs itself. It sets nothing — it has no opinion on CPU, fans, or profiles.

Three jobs:

**1. Enumerate power devices.** Yours:

```
/org/freedesktop/UPower/devices/battery_BAT0     the real battery
/org/freedesktop/UPower/devices/line_power_AC0   the charger jack
/org/freedesktop/UPower/devices/DisplayDevice    a synthetic composite
```

`DisplayDevice` is not hardware — it's UPower merging everything into one "what should the status bar show" object. That's what your shell binds to, and it's the one whose `state` went stale.

It also picks up peripherals. Your headphones are in there: `history-rate-WH-CH520-E8:9E:13:50:05:ED.dat`. That's how a desktop shows a Bluetooth device's battery.

**2. Poll and broadcast.** It reads sysfs every ~30 s (`NoPollBatteries=false`) and emits `PropertiesChanged` on D-Bus for whatever moved. It also does the arithmetic sysfs doesn't provide — `time to empty: 1.8 hours` is UPower dividing remaining energy by observed drain rate, not a hardware register. And it keeps history: `/var/lib/upower/history-rate-ASUS_Battery-75.dat` is where the week of drain samples I quoted came from.

**3. Low-battery policy.** From `/etc/UPower/UPower.conf`:

```
PercentageLow=20   PercentageCritical=5   PercentageAction=2
CriticalPowerAction=Auto
```

At 2% it acts — `Auto` normally means hibernate, falling back to shutdown when hibernate is unavailable. On this machine hibernate **cannot** work: zram is the only swap, nowhere to write the image (MACHINE.md:129). So at 2% you get a hard poweroff, no warning saved. Worth knowing given you're at 30% now.

**How it sits next to the rest:**

```
sysfs / ACPI  ──►  UPower   ──►  D-Bus  ──►  quickshell deck (displays)
                     │                   ──►  ppd (reads it, hence BatteryAware: true)
                     │                   ──►  wireplumber (headphone battery)
                     └── no writes to hardware, ever
```

ppd is its mirror image: ppd writes, never reports; UPower reports, never writes. That's why the earlier stale `state` cost you battery — the deck and `syncNature()` both trusted UPower's composite, while ppd read the same daemon independently and got it right.

Like ppd, `upower.service` is `disabled` here and only runs because something asks for it on D-Bus — which is item 1 on the fix list.

---

## Q

what is upower reporting rn

---

## A

As of 16:40:03:

```
Daemon        OnBattery: true      LidIsClosed: false     v1.91.3

BAT0          state:        discharging
              percentage:   25%          (icon-name now battery-low-symbolic)
              energy:       14.58 Wh  of  58.98 Wh full
              energy-rate:  10.50 W
              time to empty: 1.4 hours
              capacity:     77.6%        (health, vs 76.0 Wh design)
              charge-end-threshold: 80%
              warning-level: none

AC0           online: no
              updated: 15:48:33  (3090 s ago — the resume from suspend re-enumerated it)
```

Headphones (`WH-CH520`) are not connected right now, so that device has no live reading — only the history file on disk.

Three things worth pulling out:

**The reporting is entirely correct.** UPower knows you're on battery at both the daemon level (`OnBattery: true`) and the device level (`state: discharging`). The bug was never UPower's — it's the shell holding a stale copy of one property.

**You've dropped a warning tier.** `icon-name` flipped to `battery-low-symbolic`, but `warning-level` is still `none` — UPower's `PercentageLow` is 20.0, so the actual low warning fires in about 30 minutes at this rate. Then critical at 5%, and the action at 2%, which on this machine means a hard poweroff, not hibernate.

**Drain has settled to 10.5 W**, near your p25 of 10.0. From 14.58 Wh remaining that's the 1.4 hours quoted. Note what you'd have had with the fix in place: `power-saver` since 10:47 would have been running `epp=power` and a 3.2 GHz cap for six hours — conservatively 1–2 Wh saved, 10–15 minutes of the runtime you're now down to.

And the deck is still showing `PLUGGED` while all of this reads `discharging`.

---

## Q

so if upower updated why didn't it change

---

## A

Two separate things happened, and neither one is a change.

**1. "updated" is a timestamp, not a delta.** AC0's `UpdateTime` moved at 15:48:33 because resume re-polled the device. `online` was `0` before and `0` after. UPower broadcasts a property only when its *value* differs from what UPower itself last held. Same value, no message.

**2. The shell doesn't watch AC0 anyway.** `SysState.qml:31` binds `UPower.displayDevice`. AC0 could scream and nothing in your shell is listening.

Here's the direct proof. I monitored the system bus for 95 seconds just now — every signal UPower emitted:

```
3 × /org/freedesktop/UPower/devices/battery_BAT0
3 × /org/freedesktop/UPower/devices/DisplayDevice

payload, every single time:
  {'UpdateTime': …, 'TimeToEmpty': …, 'EnergyRate': …, 'Energy': …}
```

`Energy`, `EnergyRate`, `TimeToEmpty`, `UpdateTime`. That's the whole set. **`State` was never mentioned once.** Neither was `Online`. Because they haven't changed — you've been discharging without interruption since before boot.

So the shell is being fed a steady drip of updates that keep the percentage bang-on-live, and not one of them carries the field it got wrong.

## The actual mechanism

```
UPower's view:   State=Discharging since boot ─────────────────────►  never changed
                                                                      → never broadcast
Shell's view:    State=Unknown (caught mid-init)  ──────────────────►  never corrected
```

D-Bus property sync is delta-based. UPower sends the difference against **its own** previous value, not against what any client believes. It has no idea a client is out of sync, so it has no reason to resend. The only repair path is a real hardware transition — plug the charger in and the shell fixes itself instantly, because *then* `State` genuinely changes and the signal finally carries it.

That is what makes this a design bug rather than a glitch: a client that mis-reads the initial full state diverges permanently, and everything that would repair it is triggered by change. Same root as the false→false problem — every self-healing mechanism in the chain is edge-triggered, and the wrong value sits on a plateau.

Which is also why the fix has to be "don't trust a meaningless value in the first place," not "listen harder." There's nothing more to listen to.

---

## Q

but clearly it had to change at some point right from unknown to discharging why did it not catch that

---

## A

Right — and that's the crux. Two possibilities, and they have different implications.

**Either the transition happened before anyone was listening.** UPower's `DisplayDevice` is *computed* — it doesn't exist until BAT0 is enumerated. During startup the composite genuinely passes through `Unknown` and lands on `Discharging` within milliseconds, and that happens *inside* activation, before UPower has even taken its bus name. Your shell triggered that activation at 10:47:01.7 and could not have had a match rule installed for a service that didn't own its name yet. D-Bus does not replay history. By the time the shell was subscribed, the change was already in the past and would never be mentioned again.

**Or the shell's copy was never fully fetched.** This one fits the evidence better. Look at what the shell's view is made of:

```
initial GetAll        →  raced with activation, returned early / errored / partial
                         → State stays at quickshell's default 0 = Unknown
subsequent deltas     →  Energy, EnergyRate, TimeToEmpty, Percentage
                         → these four get repaired, over and over, forever
```

Every field that *varies* got silently corrected by the delta stream within minutes. Every field that *doesn't vary* kept whatever the failed initial read left behind. `State` is the only one that matters and the only one that never varies.

That explains the thing that otherwise looks impossible: the same object holding a live percentage and a five-hour-stale state. It isn't one snapshot that went stale. It's a default value that the delta stream happened to overwrite in four places and not in the fifth.

**What's proven vs. inferred.** Proven: over 95 s the only fields UPower ever emitted were `UpdateTime`, `TimeToEmpty`, `EnergyRate`, `Energy` — `State` never appears once. Proven: a probe started while UPower is *already running* reads `state=0` at `Component.onCompleted` and `state=2` 2.5 s later, so the normal path works fine. Inferred: which of the two failure modes above actually bit you at 10:47:02. I can't distinguish them from the outside.

**There's a decisive test if you want it:** `systemctl restart upower`. UPower drops its bus name and retakes it, with the shell already subscribed and listening.

- If the deck flips to `BATTERY` → the shell *does* re-fetch on name reappearance, so the original miss was purely the activation window.
- If it stays `PLUGGED` → the shell never re-fetches full state after the first attempt, which is a considerably worse bug and makes the fix mandatory rather than advisable.

Fair warning: the first outcome un-sticks your deck and you lose the live reproduction. Your call whether to run it now or after we've written the fix.

Either way it doesn't change what the fix has to be. Both failure modes are the same shape — the client's copy diverged from the source with no repair path — and both are neutralised by not letting `Unknown` outrank the daemon flag.

---

## Q

upower restarted

---

## A

**Result: still `PLUGGED`, still `balanced`, still `epp=balance_power`. And the percentage updated to 23%.**

That's the second outcome, and it's the worse one.

```
16:47:01  upower stopped, bus name dropped, service restarted
16:47:31  ppd:  balanced  epp=balance_power     ← unchanged, syncNature never fired
16:47:xx  deck: PLUGGED · 23%                   ← state stale, percentage live
          shell log: nothing. No disconnect, no reconnect, no error.
```

The shell did not notice UPower died. Not one line in its log.

## Why the restart changed nothing

D-Bus signal matching is by **object path and interface**, not by which process is sending. UPower's replacement takes the same name and emits on the same paths. From quickshell's side there is no observable event at all — the deltas simply resume:

```
old upower: PropertiesChanged /devices/DisplayDevice {Energy, EnergyRate, …}
            ✗ dies
new upower: PropertiesChanged /devices/DisplayDevice {Energy, EnergyRate, …}
            ↑ same path, same interface — the client cannot tell these apart
```

No `NameOwnerChanged` handling, no re-fetch, no full `GetAll` against the fresh daemon. The stale `State` from 10:47:02 just carries on being applied to a live delta stream.

## What this proves

Stronger than the boot race I described. The failure isn't "the shell was unlucky during activation" — it's that **quickshell's UPower binding has no resynchronisation path at all.** Whatever it holds after the first read, it holds for the life of the process, for every property that never changes. A fresh process gets it right (my probe read `state=2`), a running one can never recover.

Consequences:

- The only thing that fixes it today is restarting the shell. Not restarting UPower, not suspend/resume, not plugging in for a moment — well, plugging in *would* fix it, because that produces a genuine `State` delta. But nothing short of an actual hardware transition.
- It will recur on any boot where the shell wins the race against UPower activation. That's every boot where you're on battery, since the shell is what *activates* UPower.
- The `UPower.onBattery` fallback in `SysState.qml:41` is subject to exactly the same trap. Which is why the fix should not lean on it alone.

## What that does to the fix list

Item 1 gets promoted from tidiness to necessity: **`systemctl enable upower power-profiles-daemon`**. If UPower is already running when the shell starts, the shell's first read is against a fully-initialised daemon and the race cannot happen. That single change removes the entry condition for the whole class.

Item 2 — **AC→profile in a udev rule** — is now clearly right rather than merely cleaner. udev is edge-triggered by the kernel with a coldplug pass at boot; it does not care what the shell believes, and it keeps working when the shell is confused.

Item 3 — the ternary fix — is still worth doing for display correctness, but treat `UPower.onBattery` as a fallback of equal fragility. If you want the deck to be genuinely trustworthy, read `/sys/class/power_supply/AC0/online` directly rather than trusting any cached D-Bus property.

Your instinct at the start of this was right: patching the ternary alone would have looked like a fix, held until the next boot on battery, and taught you nothing about why.

---

## Q

please save the transcript of this chat somewhere so I can reference it

---

