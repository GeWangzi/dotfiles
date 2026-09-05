#!/usr/bin/env bash
# Link every stow package in this repo into $HOME. Safe to re-run: --restow
# turns an already-linked package into a no-op.
#
# Assumes the repo is already cloned (see INSTALL.md step 2). Installs stow
# via pacman if it is missing. Does not run system/install.sh; that needs
# root and is a separate, deliberate step.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

if ! command -v stow >/dev/null 2>&1; then
  sudo pacman -S --needed --noconfirm stow
fi

# Not stow packages: system/ is installed by system/install.sh, docs/ is prose.
skip=(system docs)

for dir in */; do
  pkg=${dir%/}
  [[ " ${skip[*]} " == *" $pkg "* ]] && continue
  # On a conflict (a real file where stow wants a symlink) stow exits non-zero
  # and names the file; we stop there rather than --adopt on the user's behalf.
  stow -t "$HOME" --restow "$pkg"
done

echo "bootstrap: all packages linked into $HOME"
