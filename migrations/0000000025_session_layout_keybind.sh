#!/bin/bash
set -eEo pipefail

echo "melk: Session-layout keybind — SUPER+SHIFT+L arranges herdr / browser / RTM+cal / gmail / grouped comms"

# ── WHY ──────────────────────────────────────────────────────────────────────
# One keystroke (SUPER+SHIFT+L) to lay out my standard working set:
#   ws1  herdr        (terminal workspace manager — needs a real TTY, so run in Alacritty)
#   ws2  browser      (default web browser)
#   ws8  Remember The Milk (left) + Google Calendar (right), side by side (two tiles)
#   ws9  Gmail        (on its own)
#   ws10 (#0)  Obsidian + Telegram + Slack + WhatsApp, tabbed into ONE group, in that order
# Already-open apps are left alone (nothing is duplicated); focus ends on the ws10 group.
#
# Depends on apps installed by earlier migrations / stock setup: herdr (0…011),
# the Gmail / Slack / Remember-The-Milk / Google-Calendar web apps, plus Telegram
# and Obsidian. On a machine missing one, that app's launch times out and is skipped.
#
# DESIGN NOTES (the non-obvious bits that made earlier attempts fail):
#   • herdr is a TERMINAL program that attaches to its `herdr server` session — a
#     bare `uwsm-app -- herdr` gets no TTY and never shows a window. It's launched
#     inside Alacritty. Its window class is the terminal's (often plain "Alacritty"),
#     so an already-running herdr is detected by PROCESS (a client on a real tty, not
#     the daemon); a fresh one is tagged `--class herdr` only so we can wait for it.
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
#   Workspace 8 : Remember The Milk (left tile) + Google Calendar (right tile), side by side
#   Workspace 9 : Gmail (on its own)
#   Workspace 10 (#0) : Obsidian + Telegram + Slack + WhatsApp, tabbed into ONE group (that tab order)
#
# Apps that are already open are left alone — nothing is duplicated.
# Focus ends on the workspace-10 group.
#
# Placement is done by switching to each target workspace and launching there, so
# windows land correctly regardless of how uwsm-app detaches them (no exec-rule or
# post-move races). The script briefly cycles through workspaces 1, 2, 8, 9, 10 while it runs.
#
# NOTE on the two web apps: they launch via omarchy-launch-webapp, which uses
# Chromium's *default* profile. Your Slack/Gmail normally run under "Profile 2".
# If a fresh launch opens a logged-out Slack/Gmail, swap those two lines for the
# PROFILE-2 variant shown further down.

set -uo pipefail

GMAIL_WS=9      # workspace #9 — Gmail on its own
GROUP_WS=10     # workspace #0 — Obsidian + Telegram + Slack, tabbed into ONE group

# Window-class regexes (case-insensitive; used for skip-detection and grouping).
RE_HERDR='^herdr$'
RE_BROWSER='^chromium$'
RE_GMAIL='mail\.google\.com'
RE_SLACK='chrome-app\.slack\.com|(^|[^a-z])slack'
RE_TELEGRAM='telegram'
RE_OBSIDIAN='^obsidian$'
RE_WHATSAPP='web\.whatsapp\.com|(^|[^a-z])whatsapp'
RE_RTM='rememberthemilk'
RE_GCAL='calendar\.google\.com'

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

# -- ws1 : herdr (a TERMINAL app). herdr runs INSIDE a terminal, so its window
# class is the terminal's (often plain "Alacritty" when started by hand) — NOT
# reliably "herdr". So detect an already-running herdr *client* by process: one
# attached to a real tty, which excludes the `herdr server` daemon and windowless
# strays. If none is running, launch one here (tagged --class herdr so we can wait
# for its window).
hyprctl dispatch workspace 1
if ps -C herdr -o tty=,args= 2>/dev/null | awk '$1!="?" && $0 !~ /herdr server/{f=1} END{exit !f}'; then
  :                                                   # herdr already up in a terminal -> leave it
else
  hyprctl dispatch exec "uwsm-app -- alacritty --class herdr -e herdr"
  wait_win_on 1 "$RE_HERDR" || echo "session-layout: herdr never appeared on ws1" >&2
fi

# -- ws2 : browser ----------------------------------------------------------
place 2 "$RE_BROWSER" omarchy-launch-browser

# -- ws8 : Remember The Milk (left) + Google Calendar (right), side by side ---
# Not grouped — two tiles. Launch RTM first so dwindle puts it on the left and
# Calendar on the right; then enforce that order in case a re-run finds them swapped.
# (Both run under Chromium's default profile; if that opens logged-out, use the
#  Profile-2 form: chromium --profile-directory="Profile 2" --app="<url>".)
place 8 "$RE_RTM"  omarchy-launch-webapp "https://www.rememberthemilk.com/app/#list/41300145"
place 8 "$RE_GCAL" omarchy-launch-webapp "https://calendar.google.com/calendar/u/0/r"
rtm=$(addr_on 8 "$RE_RTM"); gcal=$(addr_on 8 "$RE_GCAL")
if [[ -n $rtm && -n $gcal ]]; then
  rtm_x=$(hyprctl clients -j | jq -r --arg a "$rtm" 'first(.[]|select(.address==$a)|.at[0])//0')
  gcal_x=$(hyprctl clients -j | jq -r --arg a "$gcal" 'first(.[]|select(.address==$a)|.at[0])//0')
  if (( rtm_x > gcal_x )); then                        # RTM ended up on the right -> swap them
    hyprctl dispatch focuswindow "address:$rtm"
    hyprctl dispatch swapwindow l
  fi
fi

# -- ws9 : Gmail on its own -------------------------------------------------
# (Gmail runs under Chromium's default profile; if that opens logged-out, use the
#  Profile-2 form shown below the ws10 launches.)
place "$GMAIL_WS" "$RE_GMAIL" omarchy-launch-webapp "https://mail.google.com/mail/u/0/"

# -- ws10 (#0) : launch the four apps (in tab order), then tab them into ONE group --
hyprctl dispatch workspace "$GROUP_WS"

launch_on_group() {             # launch_on_group <class-regex> <launch cmd...>
  local re="$1"; shift
  has_win "$re" && return 0                          # already open -> leave it
  hyprctl dispatch exec "$*"                         # opens on the group ws (current)
  wait_win_on "$GROUP_WS" "$re" || echo "session-layout: '$*' never appeared on ws$GROUP_WS" >&2
}

launch_on_group "$RE_OBSIDIAN" uwsm-app -- obsidian
launch_on_group "$RE_TELEGRAM" uwsm-app -- Telegram
launch_on_group "$RE_SLACK"    omarchy-launch-webapp "https://app.slack.com/client/T042VJS4DUN/C04324JQ8MR"
launch_on_group "$RE_WHATSAPP" omarchy-launch-webapp "https://web.whatsapp.com/"

# PROFILE-2 variants (use INSTEAD of the omarchy-launch-webapp lines above if the
# default-profile launch opens a logged-out Slack/Gmail/WhatsApp):
# launch_on_group "$RE_SLACK"    chromium --profile-directory="Profile 2" --app="https://app.slack.com/client/T042VJS4DUN/C04324JQ8MR"
# launch_on_group "$RE_WHATSAPP" chromium --profile-directory="Profile 2" --app="https://web.whatsapp.com/"
# place "$GMAIL_WS" "$RE_GMAIL" chromium --profile-directory="Profile 2" --app="https://mail.google.com/mail/u/0/"

# Tab the four together in the desired order. First dissolve any existing grouping
# among them (togglegroup on a member dissolves the whole group), then rebuild from
# scratch so the tab sequence is always Obsidian, Telegram, Slack, WhatsApp — even if
# some were already grouped in a different order. moveintogroup is a no-op when there's
# no group in the given direction, so trying every direction reliably merges regardless
# of the tiling layout.
targets=()
for re in "$RE_OBSIDIAN" "$RE_TELEGRAM" "$RE_SLACK" "$RE_WHATSAPP"; do
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
  hyprctl dispatch focuswindow "address:$first"       # leave the group showing its first tab (Obsidian)
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
