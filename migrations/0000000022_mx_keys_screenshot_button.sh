#!/bin/bash
set -eEo pipefail

echo "melk: MX Keys S screenshot button — bind Super+Shift+S to omarchy screenshot"

# The Logitech MX Keys S "screenshot" icon key does NOT send Print Screen.
# Without Logi Options+ (Windows/Mac only) it fires the Windows "Snip" shortcut
# Super+Shift+S. Hyprland ships that bind COMMENTED OUT under "Logitech MX Keys",
# so out of the box the modifiers get dropped and only a stray "s" reaches the
# focused window (looks like "the button just types s, no screenshot").
# See docs/2026-07-28-mx-keys-screenshot-button.md for the full evdev trace.
#
# This makes the bind active. It is layout-independent and harmless on any
# machine (Super+Shift+S is simply a useful screenshot shortcut), so there's no
# hardware guard. Idempotent: uncomments the stock line if present, otherwise
# skips if already active, otherwise appends it.

CONFIG="$HOME/.config/hypr/bindings.conf"

if [ ! -f "$CONFIG" ]; then
  echo "!! $CONFIG not found — Hyprland bindings config missing here. Skipping."
  exit 0
fi

# Matches the binding regardless of trailing comment / whitespace.
BIND_RE='bind[[:space:]]*=[[:space:]]*SUPER[[:space:]]+SHIFT[[:space:]]*,[[:space:]]*S[[:space:]]*,[[:space:]]*exec[[:space:]]*,[[:space:]]*omarchy-capture-screenshot'

if grep -qE "^[[:space:]]*${BIND_RE}" "$CONFIG"; then
  echo "Super+Shift+S screenshot bind already active — skipping."
elif grep -qE "^[[:space:]]*#[[:space:]]*${BIND_RE}" "$CONFIG"; then
  # Uncomment the stock commented line in place.
  sed -i -E "s/^([[:space:]]*)#[[:space:]]*(${BIND_RE}.*)/\1\2/" "$CONFIG"
  echo "✓ Uncommented the Super+Shift+S screenshot bind in $CONFIG"
else
  # No line present at all — append one, under the MX Keys section if it exists.
  LINE='bind = SUPER SHIFT, S, exec, omarchy-capture-screenshot       # Screenshot button (MX Keys S -> Super+Shift+S)'
  if grep -qE '^[[:space:]]*#[[:space:]]*Logitech MX Keys' "$CONFIG"; then
    sed -i -E "/^[[:space:]]*#[[:space:]]*Logitech MX Keys/a\\${LINE}" "$CONFIG"
    echo "✓ Added Super+Shift+S screenshot bind under the Logitech MX Keys section."
  else
    printf '\n# Logitech MX Keys\n%s\n' "$LINE" >>"$CONFIG"
    echo "✓ Appended a Logitech MX Keys section with the Super+Shift+S screenshot bind."
  fi
fi

# Apply live if Hyprland is running (harmless no-op otherwise).
if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 && echo "✓ Reloaded Hyprland."
fi

echo "Migration completed successfully!"
