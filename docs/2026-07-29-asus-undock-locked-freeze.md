# ASUS: undocking a *locked* session freezes input (OPEN — mitigation deferred)

**Date:** 2026-07-29
**Status:** **OPEN.** Root cause understood; durable mitigation **deferred** by choice. Interim habit-based workaround in place. Revisit if it recurs / becomes annoying.
**Device:** omarchy-asus (ASUS Vivobook 15 M1505YA), Hyprland.

---

## Observation

On 2026-07-29, undocking the laptop (removed the external monitor + USB dock + AC power) **while the session was locked** left the machine unusable: `hyprlock` redrew on the laptop panel, but **no keyboard/mouse input registered**, so the password couldn't be entered → hard power-off.

Verified from the journal:
- Machine never suspended; Bluetooth MX Keys/Master **stayed connected** (no drops) → not a device/BT-radio problem.
- The lock screen *rendered* on `eDP-1` → the compositor and panel were alive.
- Conclusion: a **compositor input-focus wedge** when the **focused/primary monitor was hot-removed** while locked.

Full incident write-up (symptom, timeline, recovery) lives in the Obsidian vault:
**Homelab/Machines/omarchy-asus.md → "Quirks and workarounds"**.

## Root cause

`~/.config/hypr/monitors.conf` makes the external **AOC ultrawide `HDMI-A-1` the primary at origin `0,0`**, with the laptop panel **`eDP-1` at negative coordinates** (`-1920,450`). Removing the origin monitor while `hyprlock` is up orphans the lock surface's input focus — it doesn't cleanly migrate to the remaining panel.

## Interim mitigations (in place now)

- **Habit:** unlock before undocking (or undock while active/unlocked). Avoids it entirely.
- **Recovery without hard reset:** SSH in over Tailscale (`100.125.156.10`) → `hyprctl dispatch focusmonitor eDP-1` (or `pkill hyprlock`).
- **Reduced one contributing factor:** the AX210 Wi-Fi firmware crash on battery is fixed (migration `0000000023`, see `docs/2026-07-29-asus-wifi-powersave-battery-ax210.md`). That doesn't fix the focus-wedge itself.

## Deferred options (pick one when we return to this)

**Option 1 — Re-anchor the layout so the always-present monitor is at origin.**
Put `eDP-1` at `0,0` and place `HDMI-A-1` at a positive offset (e.g. `eDP-1` right edge → external to its right). Then undocking never removes the `0,0` anchor.
- *Pros:* one-line `monitors.conf` change; no moving parts.
- *Cons:* changes the physical arrangement (external would sit right-of / above the laptop instead of the current layout); doesn't *guarantee* hyprlock migrates focus, just makes the removed monitor a non-anchor.

**Option 2 — `monitorremoved` failover service (preferred if we act).**
A small Hyprland `socket2` listener (systemd --user service) that, on a `monitorremoved` event for `HDMI-A-1`, runs `hyprctl dispatch focusmonitor eDP-1` (and optionally re-arms hyprlock).
- *Pros:* fixes the actual focus problem; keeps the current monitor arrangement; works while locked.
- *Cons:* more moving parts (a background listener); needs to handle hyprlock being up.

**Also worth checking when we revisit:** whether a newer Hyprland/hyprlock release already handles monitor hot-unplug-while-locked better (this system was on Hyprland 0.56-era at the time).

## If implemented later

Add it as a new `migrations/00000000NN_*.sh` (install the systemd --user unit or edit `monitors.conf`), update this doc's Status to Applied, and note it in the Obsidian quirk section.
