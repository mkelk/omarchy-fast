#!/bin/bash
set -eEo pipefail

echo "melk: Driverless network scanning for the ET-2850 (SANE + airscan + simple-scan)"

# ── WHY ──────────────────────────────────────────────────────────────────────
# The ET-2850 is an all-in-one, but the driverless print setup installs nothing
# for the scanner side, so out of the box there is no way to scan from this machine.
#
# This mirrors how printing already works: the ET-2850 advertises eSCL/AirScan over
# the SAME mDNS/DNS-SD that its IPP printer service uses (_uscan._tcp), so no Epson
# blob is needed. We install:
#   sane          — the scanner stack (libsane + backends)
#   sane-airscan  — driverless eSCL/WSD backend; auto-discovers the scanner via avahi
#                   (avahi is already running for the printer). It drops
#                   /etc/sane.d/dll.d/sane-airscan.conf, so the backend is enabled
#                   with zero manual config.
#   simple-scan   — GNOME's "Document Scanner" GUI; finds the ET-2850 automatically.
#
# All three are in the official `extra` repo — no AUR. Idempotent: only the packages
# not already present are installed, so a re-run is a no-op and needs no sudo.
#
# Note: scanning relies on the same network/mDNS reachability as the printer. If the
# scanner isn't found, it's the usual driverless caveat — printer powered on and on
# the LAN. CLI check once installed:  scanimage -L

PKGS=(sane sane-airscan simple-scan)

missing=()
for p in "${PKGS[@]}"; do
  pacman -Qi "$p" &>/dev/null || missing+=("$p")
done

if ((${#missing[@]})); then
  echo "Installing: ${missing[*]}"
  sudo pacman -S --needed --noconfirm "${missing[@]}"
  echo "✓ Installed: ${missing[*]}"
else
  echo "✓ All scanner packages already installed — nothing to do."
fi

echo "Open 'Document Scanner' (simple-scan) to scan; the ET-2850 is discovered over the network."
echo "Migration completed successfully!"
