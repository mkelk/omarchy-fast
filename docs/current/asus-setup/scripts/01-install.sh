#!/bin/bash
# Trip 2: run this ON THE OFFLINE OMARCHY MACHINE, as root (sudo).
# Installs the exact-matched system packages + the MT7902 driver,
# entirely from local files — no network required.
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Run this with sudo: sudo ./01-install.sh"
    exit 1
fi

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$KIT_DIR"

echo "[1/5] Installing exact-matched system packages (local files, offline)..."
pacman -U --noconfirm \
    "$KIT_DIR/pkgs/linux-headers-7.0.9.arch2-1-x86_64.pkg.tar.zst" \
    "$KIT_DIR/pkgs/dkms-3.4.1-1-any.pkg.tar.zst" \
    "$KIT_DIR/pkgs/patch-2.8-1-x86_64.pkg.tar.zst"

echo "[2/5] Extracting driver source..."
rm -rf mt7902_driver-main
bsdtar -xf mt7902_driver.zip

echo "[3/5] Patching installer to skip its own online dependency step..."
cd mt7902_driver-main
# deps are already installed above; the upstream script would otherwise
# call 'pacman -S ...' which needs synced repos we don't have offline.
sed -i 's/^install_deps$/echo "  (deps already installed offline, skipping)"/' install.sh
chmod +x install.sh

echo "[4/5] Running the WiFi driver installer..."
set +e
./install.sh --wifi
INSTALL_STATUS=$?
set -e

echo "[5/5] Done."
if [ "$INSTALL_STATUS" -ne 0 ]; then
    echo ""
    echo "  Primary driver install reported a failure (exit $INSTALL_STATUS)."
    echo "  Try the fallback driver instead:"
    echo "    cd \"$KIT_DIR\""
    echo "    sudo ./02-fallback-manual.sh"
else
    echo "  Reboot to load the driver:"
    echo "    sudo reboot"
fi
