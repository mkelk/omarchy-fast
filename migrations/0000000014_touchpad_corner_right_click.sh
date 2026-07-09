#!/bin/bash
set -eEo pipefail

echo "melk: Touchpad right-click — corner physical click + two-finger tap"

# This machine's touchpad (ASUS Vivobook M1505YA, ASUP1303:00 093A:3003) is a
# real clickpad: the kernel marks it INPUT_PROP_BUTTONPAD and it emits a
# physical BTN_LEFT on a hard press (verified with a raw evdev trace). It has
# no separate right button, so libinput must synthesize right-click. We enable
# BOTH independent mechanisms:
#
#   clickfinger_behavior = false  -> button-areas click method: a PHYSICAL click
#                                    (press the pad down, not a light tap) in the
#                                    lower-right corner = right-click.
#   tap_button_map       = lrm    -> tap mapping: 1-finger tap = left,
#                                    2-finger tap = right, 3-finger tap = middle.
#
# Note: a light *tap* in the corner is always a left-click (tap maps by finger
# count, not position) — the corner needs a real press. This is the input layer;
# it affects every app. Pinning both survives Omarchy config resets.

CONFIG="$HOME/.config/hypr/input.conf"

if [ ! -f "$CONFIG" ]; then
  echo "!! $CONFIG not found — Hyprland input config missing here. Skipping."
  exit 0
fi

# Ensure a setting exists inside the touchpad { } block, with the desired value.
# $1 = key, $2 = value
ensure_touchpad_setting() {
  local key="$1" val="$2"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${val}([[:space:]]|$)" "$CONFIG"; then
    echo "${key} already ${val} — skipping."
  elif grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG"; then
    sed -i -E "s/^([[:space:]]*${key}[[:space:]]*=[[:space:]]*).*/\1${val}/" "$CONFIG"
    echo "✓ Set ${key} = ${val} in $CONFIG"
  elif grep -qE '^[[:space:]]*touchpad[[:space:]]*\{' "$CONFIG"; then
    sed -i -E "/^[[:space:]]*touchpad[[:space:]]*\{/a\\    ${key} = ${val}" "$CONFIG"
    echo "✓ Inserted ${key} = ${val} into the touchpad block in $CONFIG"
  else
    echo "!! No touchpad { } block found in $CONFIG."
    echo "   Add this inside the touchpad { } block manually:"
    echo "     ${key} = ${val}"
    return 1
  fi
}

ensure_touchpad_setting clickfinger_behavior false || exit 0
ensure_touchpad_setting tap_button_map       lrm   || exit 0

# Apply live if Hyprland is running (harmless no-op otherwise).
if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 && echo "✓ Reloaded Hyprland."
fi

echo "Migration completed successfully!"
