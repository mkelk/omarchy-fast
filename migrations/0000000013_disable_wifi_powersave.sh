#!/bin/bash
set -eEo pipefail

echo "melk: Disable Wi-Fi power saving (keeps long-lived connections alive on idle links)"

# WHY: most Wi-Fi drivers (incl. the FW16/ASUS mt7921e) default to power_save=on.
# When a link goes quiet the NIC sleeps, which stalls packets for a moment and drops
# long-lived connections — e.g. the RDP session into win-fw16 dies after a few minutes
# whenever the RDP window is not the active one and its desktop is static.
#
# iwd + systemd-networkd (this system's stack) don't manage 802.11 power save, so set
# it at the driver level via a udev rule that re-applies whenever a wlan* iface appears.
# Fully repeatable, no secrets — hence a migration rather than a manual local step.

RULE="/etc/udev/rules.d/81-wifi-powersave-off.rules"
echo 'ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan*", RUN+="/usr/bin/iw dev %k set power_save off"' \
  | sudo tee "$RULE" >/dev/null
echo "✓ Installed udev rule: $RULE"

# Apply immediately to any live wlan* interface so no reboot is needed.
for w in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
  if sudo iw dev "$w" set power_save off 2>/dev/null; then
    echo "  → $w: power_save $(iw dev "$w" get power_save 2>/dev/null | awk -F': ' '/Power save/{print $2}')"
  fi
done

echo "✓ Wi-Fi power saving disabled (now + persistent across reboots)"
echo "  Note: costs a little idle battery. To revert, delete $RULE and run: sudo iw dev wlan0 set power_save on"
