#!/bin/bash
set -eEo pipefail

echo "melk: Disable mt7921/mt7925 CLC (fixes clamped TX power on DFS 5GHz channels)"

# WHY: the MediaTek mt7921/mt7925 family (this ASUS VivoBook's MT7902 runs on the
# morrownr/mt76 `mt7921e` driver) has a CLC (Country Location Control) bug. On DFS
# "radar detection" 5GHz channels (e.g. ch108/5540MHz, common in the DK/ETSI band)
# the card clamps its own TX power to ~0 dBm even though the regulatory domain allows
# 26 dBm. Symptom: RX stays fast (~290 Mbit/s) but TX collapses — tx bitrate stuck
# ~20-27 Mbit/s, hundreds of thousands of tx retries, tx failures, and painfully slow
# *uploads* to other hosts (e.g. omarchy-dell, win-fw16) while downloads look fine.
# `iw dev wlan0 info` shows `txpower 0.00 dBm` as the tell.
#
# Fix: load the driver with disable_clc=Y. This lives in the morrownr/mt76 installer's
# /etc/modprobe.d/mt76_git.conf, which defaults disable_clc=N — and which gets
# regenerated whenever the driver is (re)installed/rebuilt (DKMS). Hence a migration
# that idempotently re-asserts =Y, rather than a one-off manual edit.
#
# Trade-off: disable_clc turns off a regulatory-conformance feature. Functionally the
# community-standard workaround; keeps TX power within the domain's own advertised
# limits. Alternative (no driver flag) is to move the AP to a non-DFS channel (36/40/
# 44/48), but we don't always control the AP — so fix it at the driver here.

CONF="/etc/modprobe.d/mt76_git.conf"

if [ -f "$CONF" ]; then
  # Flip disable_clc=N -> =Y on both the mt7921 and mt7925 common-module lines.
  sudo sed -i -E 's/^(options mt792[15]_common_git .*disable_clc=)N\b/\1Y/' "$CONF"
else
  # No installer file yet (driver not installed via morrownr) — create a minimal one.
  printf '%s\n%s\n' \
    'options mt7921_common_git disable_clc=Y' \
    'options mt7925_common_git disable_clc=Y' | sudo tee "$CONF" >/dev/null
fi

# Ensure both lines exist and are =Y even if the file layout differs from expected.
for mod in mt7921_common_git mt7925_common_git; do
  if ! grep -qE "^options $mod .*disable_clc=Y\b" "$CONF"; then
    echo "options $mod disable_clc=Y" | sudo tee -a "$CONF" >/dev/null
  fi
done

echo "✓ $CONF now sets disable_clc=Y:"
grep -nE 'disable_clc=' "$CONF" | sed 's/^/    /'

# Apply now by reloading the driver stack so the new param is read (wifi will blip).
# Guarded: if the module can't be hot-removed, the config still applies on next boot.
if lsmod | grep -q '^mt7921e_git\b'; then
  echo "Reloading mt7921e driver to apply immediately (wifi drops for a few seconds)..."
  if sudo modprobe -r mt7921e_git 2>/dev/null; then
    sudo modprobe -r mt7921_common_git 2>/dev/null || true
    if sudo modprobe mt7921e_git 2>/dev/null; then
      echo "✓ Driver reloaded"
    else
      echo "⚠ Reload failed to re-add module — reboot to bring wifi back with the fix"
    fi
  else
    echo "⚠ Could not hot-reload (module busy) — change applies on next reboot"
  fi
else
  echo "  (mt7921e_git not currently loaded; change applies when it next loads)"
fi

echo "✓ Done. Verify after reconnect:"
echo "    iw dev wlan0 info | grep txpower        # should no longer read 0.00 dBm"
echo "    iw dev wlan0 station dump | grep -E 'tx bitrate|tx retries|tx failed'"
