#!/bin/bash
set -eEo pipefail

echo "Install Warp Terminal"

# Warp ships as two packages: `warp-terminal` (the binary release, which some
# machines already have) and `warp-terminal-bin` (AUR). Either one satisfies us.
# Installing the AUR package on top of an existing `warp-terminal` fails with a
# /usr/bin/warp-terminal file conflict — so accept whichever is already present
# and only reach for the AUR build when neither is installed.
if pacman -Q warp-terminal &>/dev/null || pacman -Q warp-terminal-bin &>/dev/null; then
  echo "✓ Warp already installed — skipping."
else
  yay -S --noconfirm --needed warp-terminal-bin
fi
