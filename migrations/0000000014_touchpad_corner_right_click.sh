#!/bin/bash
set -eEo pipefail

echo "melk: Touchpad right-click via lower-right corner (not two-finger click)"

# Omarchy ships clickfinger_behavior = true, which maps right-click to a
# TWO-FINGER click and disables the classic lower-right-corner right-click.
# Pressing the corner then just registers as a plain left click (button 0),
# so right-click appears "broken" system-wide (herdr, RDP, browsers, ...).
# Setting it false switches libinput to button-areas: lower-right corner =
# right-click. This is the input layer; it affects every app.

CONFIG="$HOME/.config/hypr/input.conf"

if [ ! -f "$CONFIG" ]; then
  echo "!! $CONFIG not found — Hyprland input config missing here. Skipping."
  exit 0
fi

if grep -qE '^[[:space:]]*clickfinger_behavior[[:space:]]*=[[:space:]]*false' "$CONFIG"; then
  echo "clickfinger_behavior already false (corner right-click) — skipping."
elif grep -qE '^[[:space:]]*clickfinger_behavior[[:space:]]*=[[:space:]]*true' "$CONFIG"; then
  sed -i -E 's/^([[:space:]]*clickfinger_behavior[[:space:]]*=[[:space:]]*)true/\1false/' "$CONFIG"
  echo "✓ Set clickfinger_behavior = false in $CONFIG"
else
  echo "!! No clickfinger_behavior setting found in $CONFIG."
  echo "   Add this inside the touchpad { } block manually:"
  echo "     clickfinger_behavior = false"
  exit 0
fi

# Apply live if Hyprland is running (harmless no-op otherwise).
if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 && echo "✓ Reloaded Hyprland."
fi

echo "Migration completed successfully!"
