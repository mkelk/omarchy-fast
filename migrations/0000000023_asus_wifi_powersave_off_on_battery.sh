#!/bin/bash
set -eEo pipefail

echo "melk: Keep Wi-Fi power_save OFF on battery too (AX210 firmware-crash fix)"

# ── ASUS-ONLY ────────────────────────────────────────────────────────────────
# ASUS Vivobook (omarchy-asus) hardware tweak. No-op / safe on any other machine.
if ! grep -qi asus /sys/class/dmi/id/sys_vendor 2>/dev/null; then
  echo "Skipping: ASUS-specific migration (this is not an ASUS machine)."
  exit 0
fi

# WHY: This machine's Wi-Fi is an Intel AX210 (iwlwifi). With 802.11 power_save
# enabled it periodically throws firmware crashes ("iwlwifi ... Microcode SW error
# detected. Restarting") — seen 13× in the journal. Because the AX210 is a combined
# Wi-Fi+BT chip, such a crash can also drop the Bluetooth keyboard/mouse.
#
# migration 0000000013 already forces power_save OFF whenever a wlan* iface appears
# (udev rule 81-wifi-powersave-off.rules). BUT stock Omarchy also ships
# /etc/udev/rules.d/99-wifi-powersave.rules which RE-ENABLES power_save on battery
# (power_supply Mains online==0) and disables it on AC (online==1). Sorting after 81-,
# the 99- rule wins on every AC->battery transition. On 2026-07-29, undocking (=> on
# battery) re-enabled power_save; the AX210 later crashed. See:
#   - omarchy-fast docs/2026-07-29-asus-wifi-powersave-battery-ax210.md
#   - Obsidian: Homelab/Machines/omarchy-asus.md ("Quirks and workarounds")
#
# Fix: rewrite 99-wifi-powersave.rules so BOTH power transitions DISABLE power_save.
# Idempotent: only rewrites if the "on" (battery-enable) behavior is still present.

RULE="/etc/udev/rules.d/99-wifi-powersave.rules"
PS_BIN="$HOME/.local/share/omarchy/bin/omarchy-wifi-powersave"

if [ ! -f "$RULE" ]; then
  echo "$RULE not present — nothing re-enables power_save here. Skipping."
  exit 0
fi

if ! grep -q 'omarchy-wifi-powersave on' "$RULE"; then
  echo "Battery power_save-enable already neutralized — skipping."
else
  sudo cp -a "$RULE" "${RULE}.bak.$(date +%s)"
  echo "✓ Backed up original to ${RULE}.bak.*"
  sudo tee "$RULE" >/dev/null <<EOF
# Patched by omarchy-fast migration 0000000023: keep Wi-Fi power_save OFF on
# battery too. The AX210 (iwlwifi) crashes with power_save on. Stock Omarchy
# enabled it on battery (Mains online==0); both transitions now DISABLE it.
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-off-bat ${PS_BIN} off"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-off-ac ${PS_BIN} off"
EOF
  echo "✓ Rewrote $RULE (battery no longer enables power_save)."
  sudo udevadm control --reload-rules && echo "✓ Reloaded udev rules."
fi

# Apply immediately to any live wlan* interface (harmless if already off).
for w in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
  if sudo iw dev "$w" set power_save off 2>/dev/null; then
    echo "  → $w: power_save $(iw dev "$w" get power_save 2>/dev/null | awk -F': ' '/Power save/{print $2}')"
  fi
done

echo "Migration completed successfully!"
