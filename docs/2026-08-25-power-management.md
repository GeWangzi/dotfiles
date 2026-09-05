# Power management, and the stale UPower state bug

Written 2026-08-25. The question that started it: the details menu said `PLUGGED`
while the laptop had been on battery since boot. The answer turned out to be less
interesting than what it revealed about how power management is wired on this
machine, so both are recorded here.

The raw question-and-answer transcript is in
`2026-08-25-upower-session-transcript.md`.

## Who manages what

Five layers, one policy daemon.

| Layer | Owns | Notes |
| --- | --- | --- |
| `asus_wmi` firmware nodes | 80% charge cap, `platform_profile`, panel overdrive, fan curve | written by units, not persisted across reboot |
| `amd-pstate-epp` (kernel) | CPU frequency and EPP | driver only, no policy |
| `power-profiles-daemon` 0.30 | governor, EPP, `platform_profile` | the only policy daemon |
| `upower` 1.91.3 | reporting: percentage, rate, time-left | writes nothing |
| nvidia driver, `NVreg_DynamicPowerManagement=0x02` | dGPU runtime D3 | display runs on the AMD iGPU |
| quickshell `SysState.qml` | picks a ppd profile from AC state; the deck's POWER panel is the manual override | the fragile piece, see below |

Two one-shot units run at boot: `battery-charge-limit.service` writes `80` to
`charge_control_end_threshold`, and `panel-od-off.service` disables panel overdrive.
Both are enabled. Only the end threshold exists in sysfs on this laptop; the
`charge-start-threshold: 75%` that UPower reports is firmware noise with no node
behind it.

There is no TLP, no auto-cpufreq, no thermald, no asusctl. TLP was removed on
2026-08-20 after ppd's `Conflicts=` line killed it mid-init and silently took the
charge limit with it — see MACHINE.md, "The battery charge limit".

## What ppd actually does

Measured by switching profiles and reading the sysfs nodes back:

```
power-saver  gov=powersave    epp=power             platform=quiet        max 3.20 GHz
balanced     gov=powersave    epp=balance_power     platform=balanced     max 4.47 GHz
performance  gov=performance  epp=performance       platform=performance  max 4.47 GHz
```

`power-saver` is the only profile that lowers the ceiling, and that ceiling comes
from the firmware side (`platform_profile=quiet`), not from the governor. Under
`amd-pstate-epp` the governor names are misleading: `powersave` means "let the
silicon's CPPC loop choose the frequency", which is the normal full-range mode.

ppd's whole footprint is three writes — governor and EPP across all 16 logical CPUs,
and `platform_profile` once. It also reports `BatteryAware: true`, meaning it reads
UPower itself and picks the battery-side EPP within a profile. It does **not** switch
profiles on AC changes; that is deliberate, and on this machine the only thing that
would ask it to is `syncNature()` in `SysState.qml`.

## Battery numbers

Health: 58.98 Wh full against 75.998 Wh design, so 77.6%. The 80% charge cap leaves
roughly 47 Wh usable.

A week of UPower rate samples (2026-08-18 to 2026-08-25, 1558 discharge points):

```
p10  7.5W   p25 10.0W   p50 14.0W   p75 15.1W   p90 18.4W   p99 26.2W   max 50.6W
mean 13.2W
```

Which gives, from a full 80% charge:

```
light idle, browser only   7.5-10W   4.7-6.3 h
typical mixed              13-14W    3.4-3.6 h
heavy, builds              18-26W    1.8-2.6 h
gaming, dGPU loaded        50W       ~1.0 h
```

Charging averages 41 W, so 0 to 80% is about 1.2 h nominal and nearer 1.4 h with
taper. Suspend was measured over one 2 h 57 m s2idle window at roughly 0.5 W, about
1%/h, so a few days of standby.

Already correct and worth not disturbing: the dGPU is genuinely asleep (7774 s
suspended against 107 s active over 2.19 h awake), the panel is pinned to 60 Hz,
overdrive is off, and swap is zram only.

## The bug

The deck read `PLUGGED` for five hours while `AC0 online` was `0`, UPower's daemon
flag was `OnBattery: true`, and the battery device reported `discharging`.

`SysState.qml:37` decides it like this:

```
onBattery = ready ? (state is Discharging/PendingDischarge/Empty) : UPower.onBattery
```

What happened at boot:

```
10:46:55  Reached target Graphical Interface
10:46:59  wireplumber: "Failed to get percentage from UPower: NameHasNoOwner"
10:47:00  qs -d launched
10:47:01  shell.qml loads, SysState binds Quickshell.Services.UPower
          — that bind is a D-Bus call to a name with no owner
10:47:02  systemd starts upower AND power-profiles-daemon, both activated by the shell
10:47:02  upower enumerates AC0, online=0
```

Neither `upower.service` nor `power-profiles-daemon.service` is enabled. Both exist
on this machine only because a QML binding touches their D-Bus names, which means the
consumer starts the producer and is therefore guaranteed to be first.

The shell's copy of `state` was left at `Unknown (0)`. `Unknown` is in neither branch
of the test, so `onBattery` came out `false`. And because it was already `false` from
the not-ready fallback, the value went false to false — no `onOnBatteryChanged`
signal, so `syncNature()` never re-ran. The comment at `SysState.qml:400` anticipates
exactly this and expects the signal to correct it "a moment later"; that only works if
the two readings disagree, and here they agreed on the wrong answer.

Nothing repaired it afterwards because D-Bus property updates are deltas. Monitoring
the system bus for 95 seconds caught six `PropertiesChanged` signals, three on
`battery_BAT0` and three on `DisplayDevice`, each carrying exactly:

```
{'UpdateTime': ..., 'TimeToEmpty': ..., 'EnergyRate': ..., 'Energy': ...}
```

`State` never appears, because `State` never changed — the machine had been
discharging without interruption since before boot. So every field that varies gets
silently repaired by the delta stream, and the one field that does not vary keeps
whatever the failed initial read left behind. That is why the deck showed a live,
correct percentage next to a five-hour-stale plug status.

### Restarting UPower does not fix it

Tested at 16:47. UPower stopped, restarted, took its name back. Afterwards the deck
still read `PLUGGED`, ppd was still `balanced`, and the percentage was still live at
23%. The shell logged nothing at all.

D-Bus signal matching is by object path and interface, not by sender. The replacement
daemon emits on the same paths, so from the client's side nothing observable happened
— no `NameOwnerChanged` handling, no re-fetch, no fresh `GetAll`. The stale value from
10:47:02 simply carries on being applied to a live delta stream.

This makes the defect worse than a boot race. quickshell's UPower binding has no
resynchronisation path: whatever it holds after the first read, it holds for the life
of the process, for every property that never changes. A freshly started instance
reads `state=2` correctly; a running one can never recover. Short of restarting the
shell, only a genuine hardware transition — actually plugging in — produces the delta
that repairs it.

### Cost

`syncNature()` never fired, so ppd sat on `balanced` for the whole session instead of
dropping to `power-saver`. The machine ran without the 3.2 GHz cap and with
`epp=balance_power` instead of `epp=power` for six hours on battery. Conservatively
1-2 Wh, or 10-15 minutes of runtime.

## Four separate defects

Worth keeping apart, because a one-line patch only addresses the first:

1. `Unknown` outranks the fallback — `onBattery` treats a meaningless `state` as an
   answer.
2. Change-only propagation — the self-correction is edge-triggered, and the wrong
   value happens to equal the default value, so no edge occurs.
3. Policy lives in the display layer — `syncNature()` is the only thing switching ppd,
   so a cosmetic bug in a QML file costs real battery.
4. The daemons are D-Bus-activated by the UI process — ordering is whatever quickshell
   happens to do first, which is what opens the race window at all.

## The fix, in order

1. **`systemctl enable upower power-profiles-daemon`.** Both already run on every
   boot, by accident, via the shell. Making it explicit costs nothing and removes the
   entry condition for the entire class: if UPower is up before the shell starts, the
   first read is against a fully initialised daemon.
2. **Move the AC-to-profile rule into a udev rule** on `SUBSYSTEM=="power_supply"`
   calling `powerprofilesctl`. udev is edge-triggered by the kernel and coldplugs at
   boot, so there is no startup race, and the rule keeps working when the shell is
   confused or not running. `/sys/class/power_supply/AC0` exposes the needed
   `ATTR{online}`. Power policy stops living in a QML file.
3. **Then fix the ternary** in `SysState.qml:37-41`, so that `Unknown` or a not-ready
   device falls through to the daemon flag rather than being treated as an answer.
   After steps 1 and 2 this is cosmetic, which is the correct severity for a shell
   binding. Note that `UPower.onBattery` is cached over the same fragile mechanism, so
   a deck that must be trustworthy should read `/sys/class/power_supply/AC0/online`
   directly.

## asusctl, considered and declined

asusctl is AUR-only and is not a replacement for ppd — it never touches the governor
or EPP. It would add persistent charge thresholds (replacing a six-line unit), fan
curve control, and `ppt_pl1_spl` / `ppt_pl2_sppt` power-limit tuning, which ppd cannot
do at all. The cost is a second writer on `platform_profile`, which is the same
double-ownership pattern that silently ate the charge limit under TLP. Worth
revisiting only if fan curves or PPT tuning become the goal.
