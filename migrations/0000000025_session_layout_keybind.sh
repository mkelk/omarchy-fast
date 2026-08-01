#!/bin/bash
set -eEo pipefail

echo "melk: Session-layout keybind — SUPER+SHIFT+L arranges herdr / browser / grouped comms"

# ── WHY ──────────────────────────────────────────────────────────────────────
# One keystroke (SUPER+SHIFT+L) to lay out my standard working set:
#   ws1  herdr        (terminal workspace manager — needs a real TTY, so run in Alacritty)
#   ws2  browser      (default web browser)
#   ws9  Gmail + Slack + Telegram + Obsidian, tabbed into ONE group, in that order
# Already-open apps are left alone (nothing is duplicated); focus ends on ws9.
#
# Depends on apps installed by earlier migrations / stock setup: herdr (0…011),
# the Gmail & Slack web apps (0…004 / 0…005), plus Telegram and Obsidian. On a
# machine missing one, that app's launch simply times out and is skipped.
#
# DESIGN NOTES (the non-obvious bits that made earlier attempts fail):
#   • herdr is a TERMINAL program that attaches to its `herdr server` session — a
#     bare `uwsm-app -- herdr` gets no TTY and never shows a window. It's launched
#     inside Alacritty with `--class herdr` so it both runs and is detectable.
#   • Placement switches to each target workspace and launches THERE, rather than
#     using `[workspace N silent]` exec-rules, which don't survive the uwsm-app /
#     systemd handoff (the window would land on the wrong workspace).
#   • Grouping is imposed explicitly (dissolve any existing group, then rebuild in
#     order with moveintogroup) instead of relying on group:auto_group, whose
#     timing raced and left the four windows merely tiled.
#
# All changes live under ~/.config — no sudo, nothing in the read-only omarchy tree.
# Idempotent: the script is rewritten with fixed content every run; the keybind is
# inserted only if absent.

SCRIPT_DIR="$HOME/.config/omarchy/scripts"
SCRIPT="$SCRIPT_DIR/session-layout"
CONFIG="$HOME/.config/hypr/bindings.conf"

# 1) Install the session-layout script ─────────────────────────────────────────
mkdir -p "$SCRIPT_DIR"
cat > "$SCRIPT" <<'SESSION_LAYOUT_EOF'
#!/bin/bash
# session-layout — arrange my standard working set at a keystroke (SUPER SHIFT + L).
#
#   Workspace 1 : herdr (terminal workspace manager, run inside Alacritty)
#   Workspace 2 : browser (default web browser)
#   Workspace 9 : Gmail + Slack + Telegram + Obsidian, tabbed into ONE group (that tab order)
#
# Apps that are already open are left alone — nothing is duplicated.
# Focus ends on workspace 9.
#
# Placement is done by switching to each target workspace and launching there, so
# windows land correctly regardless of how uwsm-app detaches them (no exec-rule or
# post-move races). The script briefly cycles through workspaces 1, 2, 9 while it runs.
#
# NOTE on the two web apps: they launch via omarchy-launch-webapp, which uses
# Chromium's *default* profile. Your Slack/Gmail normally run under "Profile 2".
# If a fresh launch opens a logged-out Slack/Gmail, swap those two lines for the
# PROFILE-2 variant shown further down.

set -uo pipefail

GROUP_WS=9

# Window-class regexes (case-insensitive; used for skip-detection and grouping).
RE_HERDR='^herdr$'
RE_BROWSER='^chromium$'
RE_GMAIL='mail\.google\.com'
RE_SLACK='chrome-app\.slack\.com|(^|[^a-z])slack'
RE_TELEGRAM='telegram'
RE_OBSIDIAN='^obsidian$'

# -- tiny helpers -----------------------------------------------------------

# any open window (anywhere) whose class matches <regex>?
has_win() { hyprctl clients -j | jq -e --arg re "$1" 'any(.[]; (.class//"")|test($re;"i"))' >/dev/null 2>&1; }

# any window on workspace <ws> whose class matches <regex>?
has_win_on() { hyprctl clients -j | jq -e --arg re "$2" --argjson ws "$1" \
  'any(.[]; .workspace.id==$ws and ((.class//"")|test($re;"i")))' >/dev/null 2>&1; }

# address of the first window on workspace <ws> whose class matches <regex> (empty if none)
addr_on() { hyprctl clients -j | jq -r --arg re "$2" --argjson ws "$1" \
  'first(.[]|select(.workspace.id==$ws and ((.class//"")|test($re;"i")))|.address)//empty'; }

# how many group members the window at <address> has (0 = ungrouped)
grouped_len() { hyprctl clients -j | jq -r --arg a "$1" 'first(.[]|select(.address==$a)|.grouped|length)//0'; }

# block until a window matching <regex> exists on workspace <ws> (<timeout>s, default 15)
wait_win_on() {
  local ws="$1" re="$2" timeout="${3:-15}" i=0
  until has_win_on "$ws" "$re"; do
    sleep 0.2; i=$((i+1)); (( i >= timeout*5 )) && return 1
  done
}

# switch to <ws>, and if it has no window matching <regex>, launch <cmd...> there
place() {                       # place <ws> <class-regex> <launch cmd...>
  local ws="$1" re="$2"; shift 2
  hyprctl dispatch workspace "$ws"
  has_win "$re" && return 0                          # already open somewhere -> leave it
  hyprctl dispatch exec "$*"                         # opens on ws (current)
  wait_win_on "$ws" "$re" || echo "session-layout: '$*' never appeared on ws$ws" >&2
}

# -- ws1 : herdr (a TERMINAL app -> run inside Alacritty, tagged class "herdr") --
place 1 "$RE_HERDR"   uwsm-app -- alacritty --class herdr -e herdr

# -- ws2 : browser ----------------------------------------------------------
place 2 "$RE_BROWSER" omarchy-launch-browser

# -- ws9 : launch the four apps (in tab order), then tab them into ONE group --
hyprctl dispatch workspace "$GROUP_WS"

launch_on_ws9() {               # launch_on_ws9 <class-regex> <launch cmd...>
  local re="$1"; shift
  has_win "$re" && return 0                          # already open -> leave it
  hyprctl dispatch exec "$*"                         # opens on ws9 (current)
  wait_win_on "$GROUP_WS" "$re" || echo "session-layout: '$*' never appeared on ws$GROUP_WS" >&2
}

launch_on_ws9 "$RE_GMAIL"    omarchy-launch-webapp "https://mail.google.com/mail/u/0/"
launch_on_ws9 "$RE_SLACK"    omarchy-launch-webapp "https://app.slack.com/client/T042VJS4DUN/C04324JQ8MR"
launch_on_ws9 "$RE_TELEGRAM" uwsm-app -- Telegram
launch_on_ws9 "$RE_OBSIDIAN" uwsm-app -- obsidian

# PROFILE-2 variants (use INSTEAD of the two omarchy-launch-webapp lines above if
# the default-profile launch opens a logged-out Slack/Gmail):
# launch_on_ws9 "$RE_GMAIL" chromium --profile-directory="Profile 2" --app="https://mail.google.com/mail/u/0/"
# launch_on_ws9 "$RE_SLACK" chromium --profile-directory="Profile 2" --app="https://app.slack.com/client/T042VJS4DUN/C04324JQ8MR"

# Tab the four together in the desired order. First dissolve any existing grouping
# among them (togglegroup on a member dissolves the whole group), then rebuild from
# scratch so the tab sequence is always Gmail, Slack, Telegram, Obsidian — even if
# some were already grouped in a different order. moveintogroup is a no-op when
# there's no group in the given direction, so trying every direction reliably merges
# regardless of the tiling layout.
targets=()
for re in "$RE_GMAIL" "$RE_SLACK" "$RE_TELEGRAM" "$RE_OBSIDIAN"; do
  a=$(addr_on "$GROUP_WS" "$re"); [[ -n $a ]] && targets+=("$a")
done

if (( ${#targets[@]} >= 2 )); then
  # dissolve any current grouping so we can impose a clean order
  for addr in "${targets[@]}"; do
    if (( $(grouped_len "$addr") > 0 )); then
      hyprctl dispatch focuswindow "address:$addr"
      hyprctl dispatch togglegroup
    fi
  done
  # rebuild the group in target order
  first="${targets[0]}"
  hyprctl dispatch focuswindow "address:$first"; hyprctl dispatch togglegroup
  for addr in "${targets[@]:1}"; do
    for dir in l r u d; do
      hyprctl dispatch focuswindow "address:$addr"
      hyprctl dispatch moveintogroup "$dir"
      (( $(grouped_len "$addr") > 0 )) && break
    done
  done
  hyprctl dispatch focuswindow "address:$first"       # leave the group showing its first tab (Gmail)
fi

hyprctl dispatch workspace "$GROUP_WS"                # end focused on the group
command -v notify-send >/dev/null && notify-send -t 2000 -a "Session layout" "Session layout" "Workspaces arranged"
SESSION_LAYOUT_EOF
chmod +x "$SCRIPT"
echo "✓ Installed session-layout script: $SCRIPT"

# 2) Bind SUPER+SHIFT+L to it (idempotent) ─────────────────────────────────────
# SUPER+SHIFT+L is unbound in stock Omarchy, so no unbind is needed.
BIND_LINE='bindd = SUPER SHIFT, L, Session layout, exec, ~/.config/omarchy/scripts/session-layout'

if [ ! -f "$CONFIG" ]; then
  echo "!! $CONFIG not found — script installed, but couldn't add the keybind. Skipping."
elif grep -qF 'scripts/session-layout' "$CONFIG"; then
  echo "Session-layout keybind already present — skipping."
elif grep -qE '^[[:space:]]*#[[:space:]]*Add extra bindings' "$CONFIG"; then
  sed -i -E "/^[[:space:]]*#[[:space:]]*Add extra bindings/a\\${BIND_LINE}" "$CONFIG"
  echo "✓ Added SUPER+SHIFT+L (Session layout) bind under 'Add extra bindings' in $CONFIG"
else
  printf '\n# Session layout\n%s\n' "$BIND_LINE" >>"$CONFIG"
  echo "✓ Appended SUPER+SHIFT+L (Session layout) bind to $CONFIG"
fi

# Apply live if Hyprland is running (harmless no-op otherwise).
if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 && echo "✓ Reloaded Hyprland."
fi

echo "Migration completed successfully!"
