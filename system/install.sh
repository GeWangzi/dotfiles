#!/usr/bin/env bash
#
# Install the system-level (/etc) configuration that the stow packages in this
# repo cannot cover, because it lives outside $HOME and is owned by root.
#
# Everything here is inert: files are written, but no service is started or
# restarted, and no tuning is applied to a running system. The changes take
# effect at the next boot. That is deliberate -- several of these files control
# audio gain and power management, and restarting those services live has a
# history of leaving the machine in a worse state than it started in.
#
# Every file that already exists is backed up to <file>.bak-<timestamp> before
# being overwritten, so a bad run can always be undone by hand.
#
# Usage:
#   sudo bash system/install.sh            # install
#   sudo bash system/install.sh --dry-run  # show what would change, touch nothing
#
# IMPORTANT: most of this is specific to the ASUS ROG Zephyrus G14 (GA401QM) --
# a WD Green SN350 NVMe drive, a Realtek ALC285 codec, and an MT7921 wifi
# adapter. On different hardware the NVMe and panel-overdrive pieces are at best
# useless and at worst harmful. The script checks the DMI product name and
# refuses to continue on a mismatch unless --force is passed.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [[ $DRY_RUN -eq 0 && $EUID -ne 0 ]]; then
  echo "This script writes to /etc and must be run as root." >&2
  echo "Try: sudo bash $0" >&2
  exit 1
fi

say() { printf '%s\n' "$*"; }
act() { if [[ $DRY_RUN -eq 1 ]]; then say "  would: $*"; else "$@"; fi; }

# --- hardware check ----------------------------------------------------------

PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
EXPECTED="ROG Zephyrus G14 GA401QM_GA401QM"

if [[ "$PRODUCT" != *"GA401QM"* && $FORCE -eq 0 ]]; then
  cat >&2 <<EOF
This machine reports its product name as:

    $PRODUCT

The configuration in this directory was written for a $EXPECTED. In particular:

  * 99-nvme.conf and the grub NVMe kernel parameter work around a controller
    hang specific to the WD Green SN350 in that laptop.
  * panel-od-off.service writes to an asus-nb-wmi sysfs path that only exists
    on ASUS laptops.
  * 02-profile.conf assumes the G14's platform-profile fan curves.

Re-run with --force if you know these apply to this machine, or install the
files you want by hand -- they are plain text and each one carries a comment
explaining why it exists.
EOF
  exit 1
fi

# --- plain file installs -----------------------------------------------------

install_file() {
  local rel="$1"
  local src="$SRC/etc/$rel"
  local dst="/etc/$rel"

  if [[ ! -f "$src" ]]; then
    say "  skip $dst (not present in repo)"
    return
  fi

  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    say "  ok   $dst (already matches)"
    return
  fi

  if [[ -e "$dst" ]]; then
    say "  back up $dst -> $dst.bak-$STAMP"
    act cp -p "$dst" "$dst.bak-$STAMP"
  fi

  say "  write $dst"
  act install -D -m 0644 -o root -g root "$src" "$dst"
}

# Remove a file this repo used to install, once its settings have moved
# elsewhere. Backed up first, same as an overwrite, so a bad run is undoable.
retire_file() {
  local rel="$1"
  local dst="/etc/$rel"

  [[ -e "$dst" ]] || return 0

  say "  back up $dst -> $dst.bak-$STAMP"
  act cp -p "$dst" "$dst.bak-$STAMP"
  say "  remove $dst (superseded)"
  act rm -f "$dst"
}

say "Installing /etc configuration from $SRC"
say ""

# NetworkManager is deliberately left alone. It runs stock: the wpa_supplicant
# backend, no drop-in configuration, and wpa_supplicant started on demand
# through D-Bus activation rather than an enabled unit.
#
# The drop-ins below are ones older revisions of this repo installed. They are
# removed rather than installed, so a machine set up by an older revision
# converges on the stock setup. See the git history for why they existed.
say "NetworkManager (stock -- removing drop-ins this repo used to install):"
retire_file NetworkManager/conf.d/local.conf
retire_file NetworkManager/conf.d/wifi-backend.conf
retire_file NetworkManager/conf.d/wifi-powersave.conf
retire_file NetworkManager/conf.d/dns.conf
retire_file NetworkManager/conf.d/wifi-dhcp.conf

say ""
say "sysctl (full SysRq, so a hung system can be rebooted cleanly):"
install_file sysctl.d/99-sysrq.conf

say ""
say "polkit (timezone changes from the shell menu, no password dialog):"
install_file polkit-1/rules.d/49-rpg-shell.rules

say ""
say "systemd units:"
install_file systemd/system/panel-od-off.service
install_file systemd/system/battery-charge-limit.service
install_file systemd/system/power-profile-ac.service
install_file systemd/system/sing-box.service.d/override.conf

say ""
say "udev (udevd reloads rules on its own):"
install_file udev/rules.d/80-nvidia-runtime-pm.rules
install_file udev/rules.d/85-power-profile-ac.rules

say ""
say "modprobe (NVIDIA runtime D3; pairs with the udev rule above, takes effect at boot):"
install_file modprobe.d/nvidia-pm.conf

# --- grub kernel command line ------------------------------------------------
#
# /etc/default/grub is not copied wholesale: a fresh install's copy carries
# distribution defaults and a root filesystem type that may not match this one.
# Only the two GRUB_CMDLINE lines are rewritten, and only if they differ.

say ""
say "GRUB kernel command line:"

GRUB_FILE=/etc/default/grub
WANT_LINUX='GRUB_CMDLINE_LINUX="zswap.enabled=0 rootfstype=ext4 nvme_core.default_ps_max_latency_us=0"'
WANT_DEFAULT='GRUB_CMDLINE_LINUX_DEFAULT="loglevel=7"'
GRUB_CHANGED=0

if [[ ! -f "$GRUB_FILE" ]]; then
  say "  skip $GRUB_FILE (no GRUB on this machine -- if it boots with"
  say "       systemd-boot, put the same parameters in the kernel cmdline there:"
  say "       zswap.enabled=0 nvme_core.default_ps_max_latency_us=0)"
else
  set_grub_line() {
    local key="$1" want="$2"
    local have
    have="$(grep -E "^${key}=" "$GRUB_FILE" || true)"

    if [[ "$have" == "$want" ]]; then
      say "  ok   $key (already set)"
      return
    fi

    if [[ $GRUB_CHANGED -eq 0 ]]; then
      say "  back up $GRUB_FILE -> $GRUB_FILE.bak-$STAMP"
      act cp -p "$GRUB_FILE" "$GRUB_FILE.bak-$STAMP"
      GRUB_CHANGED=1
    fi

    if [[ -n "$have" ]]; then
      say "  rewrite $key"
      act sed -i "s|^${key}=.*|${want}|" "$GRUB_FILE"
    else
      say "  append $key"
      act sh -c "printf '%s\n' '$want' >> '$GRUB_FILE'"
    fi
  }

  set_grub_line GRUB_CMDLINE_LINUX "$WANT_LINUX"
  set_grub_line GRUB_CMDLINE_LINUX_DEFAULT "$WANT_DEFAULT"

  if [[ $GRUB_CHANGED -eq 1 ]]; then
    say ""
    say "  NOTE: rootfstype=ext4 above assumes an ext4 root. Check with"
    say "        'findmnt -no FSTYPE /' and edit $GRUB_FILE if it differs,"
    say "        BEFORE regenerating the config -- a wrong rootfstype will"
    say "        stop the machine booting."
    say ""
    say "  Then regenerate the boot config yourself:"
    say "        sudo grub-mkconfig -o /boot/grub/grub.cfg"
    say ""
    say "  This script does not run that for you. It rewrites the file that"
    say "  decides whether the machine boots at all, and it should be run only"
    say "  once the rootfstype line has been eyeballed."
  fi
fi

# --- reload what can be reloaded safely --------------------------------------

say ""
if [[ $DRY_RUN -eq 1 ]]; then
  say "Dry run: nothing was written."
else
  systemctl daemon-reload
  say "systemd unit files reloaded (no service started or restarted)."
fi

# --- what is left to do by hand ----------------------------------------------

cat <<'EOF'

Done. Nothing has been started -- these take effect at the next boot.

Still to do by hand, in rough order:

0. Apply the NetworkManager settings without waiting for a reboot:

     sudo nmcli general reload conf
     NetworkManager --print-config        # confirm what actually took effect

   This is safe on a live system: it re-reads the config files and does not
   drop the current connection.

1. Enable the services. None of them are enabled by this script.

     sudo systemctl enable NetworkManager bluetooth panel-od-off
     sudo systemctl enable upower power-profiles-daemon battery-charge-limit
     sudo systemctl enable power-profile-ac
     sudo systemctl enable nvidia-suspend nvidia-resume nvidia-hibernate
     sudo systemctl enable sing-box      # only after the config below exists

     systemctl --user enable hyprpolkitagent hyprsunset
     systemctl --user enable wireplumber pipewire-pulse

2. sing-box is NOT in this repo. /etc/sing-box/config.json holds the VLESS
   server address and its UUID, so it is a credential and does not belong in a
   public git repository. Copy it from the old machine over ssh or a USB stick,
   as root, mode 0640 root:sing-box.

   After copying it, confirm the experimental.cache_file block came across:

     sudo jq -r 'paths | select(.[-1] == "cache_file") | join(".")' \
       /etc/sing-box/config.json          # expect: experimental.cache_file

   Without it the geoip-cn and geosite-cn rule sets are re-downloaded at every
   start, and when that download fails all China-bound traffic silently goes
   through the proxy instead of direct.

3. Wifi profiles are not here either -- /etc/NetworkManager/system-connections
   stores PSKs in plaintext. The most recent backup of the old machine's copy
   is /root/nm-backup-2026-08-16.tar.gz. Restore it as root, or just re-enter
   the few networks that matter.

   The eduroam profile uses PEAP/MSCHAPv2. If it will not associate on campus,
   set 802-1x.ca-cert and 802-1x.domain-suffix-match on that profile.

4. Microphone gain is tuned per codec and is not portable as a file. On an
   ALC285, install alsa-utils, then in alsamixer (F4 for the capture view) set
   'Internal Mic Boost' to 1 (10 dB) and 'Capture' to 50, and persist it with
   'sudo alsactl store'. The wireplumber soft-mixer drop-in that stops those
   values being clobbered IS in this repo -- 'stow wireplumber' installs it.

   Do not tune this mic with 'wpctl set-volume': it applies software gain and
   forces the hardware Capture control back to its maximum.

5. ~/.local/bin/connectvm is deliberately absent from this repo -- it contains
   an RDP host address and username. Copy it across by hand if it is still
   needed.

EOF
