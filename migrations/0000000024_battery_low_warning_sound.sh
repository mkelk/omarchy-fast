#!/bin/bash
set -eEo pipefail

echo "melk: Audible low-battery warning + fix boot-race PATH in the battery monitor"

# ── WHY ──────────────────────────────────────────────────────────────────────
# Two independent tweaks to Omarchy's low-battery alerting. omarchy-battery-monitor
# is a systemd --user timer (OnBootSec=1min, then every 30s) that, while discharging
# and <=10%, sends ONE critical mako notification and runs the `battery-low` hook.
#
# 1) MAKE THE WARNING AUDIBLE.
#    Stock Omarchy ships the sound hook DISABLED — as
#    ~/.config/omarchy/hooks/battery-low.d/play-warning-sound.sample, and omarchy-hook
#    skips *.sample. So the only signal is a single SILENT mako popup, trivial to miss.
#    On 2026-08-01 this machine drained to 3% with the alert unnoticed for exactly that
#    reason. We install our OWN active hook that plays the freedesktop warning chime.
#    The upstream .sample is left in place as reference (omarchy-hook ignores it).
#    Played SYNCHRONOUSLY (no backgrounding): the monitor is Type=oneshot, so systemd
#    tears down its cgroup when ExecStart returns and would kill a backgrounded player
#    mid-sound. `timeout 5` guards against a hung audio server stalling the 30s cycle.
#
# 2) FIX THE BOOT-RACE `command not found`.
#    The monitor calls omarchy-battery-remaining / omarchy-hook, which live in
#    ~/.local/share/omarchy/bin. That dir is only on PATH once the graphical session
#    imports it into the systemd --user environment. The first timer fire can beat that
#    import, so the first post-boot run dies with
#    "omarchy-battery-remaining: command not found" (seen once per boot in the journal)
#    — i.e. a <=10% battery in the first minute after boot gets NO alert at all. We pin
#    PATH via a drop-in so the service is self-sufficient regardless of login timing.
#    A drop-in (not editing the unit) so `omarchy update`/`refresh` can't clobber it.
#
# All changes live under ~/.config — no sudo, nothing in the read-only omarchy tree.
# Idempotent: both files are rewritten with fixed content on every run.

HOOK_DIR="$HOME/.config/omarchy/hooks/battery-low.d"
HOOK_FILE="$HOOK_DIR/play-warning-sound"
DROPIN_DIR="$HOME/.config/systemd/user/omarchy-battery-monitor.service.d"
DROPIN_FILE="$DROPIN_DIR/10-path.conf"

# 1) Active audible battery-low hook ───────────────────────────────────────────
mkdir -p "$HOOK_DIR"
cat > "$HOOK_FILE" <<'EOF'
#!/bin/bash
# Installed by omarchy-fast migration 0000000024: audible chime when the <=10%
# battery alert fires (omarchy-battery-monitor -> omarchy-hook battery-low). Runs
# SYNCHRONOUSLY because the caller is a Type=oneshot service (a backgrounded player
# gets killed on cgroup teardown). Degrades to silence if no player/sound exists.
SOUND="/usr/share/sounds/freedesktop/stereo/dialog-warning.oga"
[[ -f $SOUND ]] || exit 0
if command -v paplay &>/dev/null; then
  timeout 5 paplay "$SOUND"
elif command -v pw-play &>/dev/null; then
  timeout 5 pw-play "$SOUND"
elif command -v mpv &>/dev/null; then
  timeout 5 mpv --no-video --really-quiet "$SOUND"
fi
exit 0
EOF
chmod +x "$HOOK_FILE"
echo "✓ Installed active battery-low sound hook: $HOOK_FILE"

# 2) PATH drop-in for the monitor service ──────────────────────────────────────
mkdir -p "$DROPIN_DIR"
cat > "$DROPIN_FILE" <<'EOF'
# Installed by omarchy-fast migration 0000000024: pin PATH so omarchy-battery-monitor
# can find omarchy-battery-remaining / omarchy-hook even on the first post-boot timer
# fire, before the graphical session imports PATH into the systemd --user environment.
[Service]
Environment=PATH=%h/.local/share/omarchy/bin:%h/.local/bin:/usr/local/bin:/usr/bin:/bin
EOF
echo "✓ Installed PATH drop-in: $DROPIN_FILE"

# Apply now (harmless if the user manager isn't reachable, e.g. in a chroot/install).
if systemctl --user daemon-reload 2>/dev/null; then
  echo "✓ Reloaded systemd --user (drop-in active on next monitor run)."
else
  echo "⚠ Could not reload systemd --user now; it will apply on next login."
fi

echo "Migration completed successfully!"
