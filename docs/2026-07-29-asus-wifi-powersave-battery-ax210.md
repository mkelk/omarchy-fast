# AX210 Wi-Fi: keep power_save OFF on battery too

**Date:** 2026-07-29
**Status:** Applied on the Vivobook via migration `0000000023` (ASUS-guarded). Persistent across reboots.
**Device:** Intel **AX210** (`iwlwifi`) — combined Wi-Fi + Bluetooth. (Replaced the original MT7902; migration 13's comment still references the old `mt7921e`.)

---

## TL;DR

The AX210 throws firmware crashes (`iwlwifi … Microcode SW error detected. Restarting`) when 802.11 **power_save is enabled** — **13 occurrences** in the journal. Migration 13 already forces power_save **off on interface-add**, but stock Omarchy's `/etc/udev/rules.d/99-wifi-powersave.rules` **re-enables it on battery**. Migration 23 rewrites that rule so **both** AC and battery transitions keep power_save **off**.

## Root cause / the conflict

Two udev rules disagree:

| File | Trigger | Effect |
|---|---|---|
| `81-wifi-powersave-off.rules` (migration 13) | `net add`, `wlan*` | power_save **off** |
| `99-wifi-powersave.rules` (stock Omarchy) | `power_supply` Mains `online==0` (battery) | power_save **on** ← problem |
| `99-wifi-powersave.rules` (stock Omarchy) | Mains `online==1` (AC) | power_save off |

`81-` only fires when the interface appears; it does **not** re-fire on AC↔battery changes. So every time the laptop goes to battery, the `99-` rule wins and enables power_save → AX210 instability.

This bit on **2026-07-29**: undocking put the laptop on battery (`omarchy-wifi-powersave on` fired at 07:18:32), and the AX210 crashed (07:23:13). It was a contributing factor to a frozen locked session that morning — see the primary write-up in the Obsidian vault: **Homelab/Machines/omarchy-asus.md → "Quirks and workarounds"** (undock-while-locked hyprlock input freeze).

## The fix

`migrations/0000000023_asus_wifi_powersave_off_on_battery.sh` (idempotent, ASUS-guarded) rewrites `99-wifi-powersave.rules` so both Mains transitions call `omarchy-wifi-powersave off`, backs up the original, reloads udev, and applies live.

## Verify

```bash
cat /etc/udev/rules.d/99-wifi-powersave.rules        # both lines should end in "... off"
iw dev wlan0 get power_save                          # -> "Power save: off"
# after unplugging AC, re-check — must still say off:
iw dev wlan0 get power_save
journalctl -k | grep -c 'Microcode SW error'         # should stop growing
```

## Revert

Restore `/etc/udev/rules.d/99-wifi-powersave.rules` from its `.bak.*` backup and `sudo udevadm control --reload-rules`.

## Note

If a future `omarchy update` rewrites `99-wifi-powersave.rules` back to the stock (battery-enables) form, just re-run this migration — it detects the `omarchy-wifi-powersave on` string and re-patches.
