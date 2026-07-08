#!/bin/bash
# Trip 1: run this ON THE OFFLINE OMARCHY MACHINE. No network needed.
# It just reads local system state and writes a report file next to itself
# (i.e. onto the USB stick, if that's where you're running it from).

OUT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/system-report.txt"

{
    echo "=== kernel ==="
    uname -r
    uname -m
    echo
    echo "=== installed kernel package ==="
    pacman -Q linux 2>&1
    echo
    echo "=== already installed? ==="
    pacman -Q linux-headers 2>&1
    pacman -Q dkms 2>&1
    pacman -Q zstd 2>&1
    pacman -Q git 2>&1
    echo
    echo "=== base-devel group ==="
    pacman -Qg base-devel 2>&1
    echo
    echo "=== compilers present? ==="
    which gcc make 2>&1
    echo
    echo "=== wifi hardware ==="
    lspci -k | grep -A3 -i network
    echo
    echo "=== rfkill ==="
    rfkill list
    echo
    echo "=== pacman mirror/arch ==="
    cat /etc/pacman.d/mirrorlist 2>/dev/null | grep -m1 "^Server"
} > "$OUT" 2>&1

echo "Done. Report written to: $OUT"
echo "Bring the USB stick back and tell Claude it's ready."
