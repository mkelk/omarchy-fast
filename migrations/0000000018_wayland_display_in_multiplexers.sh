#!/bin/bash
set -eEo pipefail

echo "melk: Restore WAYLAND_DISPLAY inside terminal multiplexers (herdr/tmux)"

# WHY: multiplexers like herdr (the agent multiplexer) and tmux run a persistent
# server; the panes it spawns inherit the *server's* environment, which is missing
# WAYLAND_DISPLAY. GUI clipboard tools (wl-paste/wl-copy) then can't connect to the
# compositor, even though the wayland socket is sitting right there in
# $XDG_RUNTIME_DIR. The concrete symptom: running Claude Code in a herdr pane,
# pressing Ctrl+V to paste an Omarchy screenshot (grim|wl-copy puts image/png on the
# clipboard) fails with "No image in clipboard" — Claude Code shells out to wl-paste,
# which has no WAYLAND_DISPLAY and finds nothing.
#
# Fix: for every interactive shell, if WAYLAND_DISPLAY is unset, discover the live
# wayland socket in $XDG_RUNTIME_DIR and export it. Guarded by a marker so re-running
# the migration (or running it after a manual edit) is a no-op. Idempotent, no secrets.

BASHRC="$HOME/.bashrc"
MARKER="# omarchy-fast: WAYLAND_DISPLAY passthrough for multiplexers"

if [ ! -f "$BASHRC" ]; then
  echo "!! $BASHRC not found — skipping."
  exit 0
fi

if grep -qF "$MARKER" "$BASHRC"; then
  echo "WAYLAND_DISPLAY guard already present in $BASHRC — skipping."
  exit 0
fi

cat >>"$BASHRC" <<'EOF'

# omarchy-fast: WAYLAND_DISPLAY passthrough for multiplexers
# Multiplexers like herdr/tmux run a persistent server whose panes inherit an
# environment missing WAYLAND_DISPLAY. GUI clipboard tools (wl-paste) then can't
# reach the compositor, so Claude Code's Ctrl+V image paste reports "No image in
# clipboard". Restore it from the live wayland socket for every interactive shell.
if [ -z "$WAYLAND_DISPLAY" ] && [ -n "$XDG_RUNTIME_DIR" ]; then
  for _s in "$XDG_RUNTIME_DIR"/wayland-*; do
    case "$_s" in *.lock) continue ;; esac
    [ -S "$_s" ] && export WAYLAND_DISPLAY="${_s##*/}" && break
  done
  unset _s
fi
EOF

echo "✓ Added WAYLAND_DISPLAY guard to $BASHRC"
echo "  Open a fresh shell (or new herdr pane) and relaunch Claude Code to pick it up."
echo "Migration completed successfully!"
