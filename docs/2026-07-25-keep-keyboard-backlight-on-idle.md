# Keep the keyboard backlight lit through idle/lock (Vivobook)

**Date:** 2026-07-25
**Status:** Applied on the Vivobook. User-space only — survives `omarchy update`. **No omarchy migration** (deliberately a local doc, not a source change).
**Device:** `asus::kbd_backlight`

---

## TL;DR

The keyboard backlight was going dark ~2.5 min in, seemingly "when the screensaver kicks in." It was actually the **auto-lock**, not the screensaver. Fixed with a small user-space wrapper that locks the screen (and still blanks the display) but leaves the keyboard backlight untouched. hypridle points at the wrapper instead of the stock lock.

---

## Root cause

`~/.config/hypr/hypridle.conf` timeline:

- **150s** — `omarchy-launch-screensaver`
- **152s** — `omarchy-system-lock`

So the lock fires 2s after the screensaver appears → looks like the screensaver kills the light, but it's the lock.

`omarchy-system-lock`, 3s after locking, runs **both**:

```bash
omarchy-brightness-keyboard off      # brightnessctl -s (save) then set 0
omarchy-brightness-display off
```

Both are gated behind the **same** `OMARCHY_LOCK_ONLY` flag — there is no separate knob to keep the keyboard on while still blanking the screen. On unlock, `omarchy-system-wake` runs `omarchy-brightness-keyboard restore` (`brightnessctl -r`), which is why it comes back after unlock.

## The fix

A wrapper that reuses the stock lock for all the real work (hyprlock, 1Password lock, xkb reset, screensaver kill, wake-on-resume) via `OMARCHY_LOCK_ONLY=true` — which makes the stock script skip the display-off **and** keyboard-off block — then blanks **only the display** itself. The keyboard is never touched.

`~/.local/bin/omarchy-lock-keep-kbd`:

```bash
#!/bin/bash

# Lock like omarchy-system-lock, but keep the keyboard backlight lit.
# Stock omarchy-system-lock turns OFF both display and keyboard backlight 3s
# after locking, gated behind a single OMARCHY_LOCK_ONLY flag. We reuse the
# stock lock with that flag set (skips BOTH), then blank only the display.

# Pre-save the current keyboard backlight level. On unlock, omarchy-system-wake
# runs `omarchy-brightness-keyboard restore` (brightnessctl -r); without a saved
# state it prints a harmless "Error restoring device data". Saving now means the
# restore finds this (already-lit) value and is a clean no-op.
for led in /sys/class/leds/*kbd_backlight*; do
  [[ -e $led ]] && brightnessctl -sd "$(basename "$led")" >/dev/null 2>&1
  break
done

OMARCHY_LOCK_ONLY=true omarchy-system-lock "$@"

(
  sleep 3
  pidof hyprlock >/dev/null || exit 0
  omarchy-brightness-display off
) &
```

`~/.config/hypr/hypridle.conf` — point both lock entry points at the wrapper (leave `before_sleep_cmd` alone; keyboard state is irrelevant across suspend):

```diff
 general {
-    lock_cmd = omarchy-system-lock
+    lock_cmd = omarchy-lock-keep-kbd
     ...
 }

 listener {
     timeout = 152
-    on-timeout = omarchy-system-lock
+    on-timeout = omarchy-lock-keep-kbd
     on-resume = omarchy-system-wake
 }
```

Apply: `chmod +x ~/.local/bin/omarchy-lock-keep-kbd && omarchy restart hypridle`

## Notes / gotchas

- **The "Error restoring device data" message** on unlock came from wake-time `restore` finding no saved state (we no longer save-and-zero the keyboard). The wrapper's pre-save loop fixes it — restore now finds the already-lit value and no-ops.
- **Maintenance:** the wrapper re-implements the single display-off line. If a future omarchy changes *how* locking blanks the screen, glance at the wrapper.
- **Revert:** restore `~/.config/hypr/hypridle.conf` from its `.bak.*` backup and delete the wrapper.
- **Variant:** to *dim* the keyboard to a low level on lock instead of leaving it full-on, replace the display-off subshell's logic with a `brightnessctl -d "$device" set <low>` on the keyboard.
