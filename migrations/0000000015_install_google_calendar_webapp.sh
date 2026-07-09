#!/bin/bash
set -eEo pipefail

echo "melk: Install Google Calendar web-app launcher (Super+Space -> 'Calendar')"

# Mirrors the existing Gmail launcher: a standalone web-app window via
# omarchy-launch-webapp, not a browser tab. Uses account u/0 (same as Gmail).
# Icon x-office-calendar ships with the stock icon themes.

mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/google-calendar.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Google Calendar
Comment=Google Calendar
Exec=omarchy-launch-webapp "https://calendar.google.com/calendar/u/0/r"
Icon=x-office-calendar
Type=Application
Categories=Network;Calendar;Office;
StartupWMClass=calendar.google.com
DESKTOP

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

echo "✓ Installed. Launch 'Google Calendar' from Super+Space."
