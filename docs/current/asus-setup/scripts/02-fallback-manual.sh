#!/bin/bash
# Only needed if 01-install.sh's primary driver install failed.
# Builds the alternative hmtheboy154/mt7902 driver directly from the
# locally bundled source — no network, no git needed.
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Run this with sudo: sudo ./02-fallback-manual.sh"
    exit 1
fi

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$KIT_DIR"

echo "[1/4] Extracting fallback driver source..."
rm -rf mt7902-main
bsdtar -xf mt7902_fallback.zip

echo "[2/4] Building..."
cd mt7902-main
make -j"$(nproc)"

echo "[3/4] Installing module + firmware..."
make install
make install_fw 2>/dev/null || echo "  (firmware install step skipped, may already be present)"
depmod -a

echo "[4/4] Loading driver..."
rmmod mt7902e 2>/dev/null || true
rmmod mt7921e 2>/dev/null || true
modprobe mt7902e

echo ""
echo "Done. Check for a new wireless interface with: ip link show"
