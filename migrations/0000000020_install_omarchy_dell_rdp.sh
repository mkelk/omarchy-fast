#!/bin/bash
set -eEo pipefail

echo "melk: Install FreeRDP client + omarchy-dell command (RDP into omarchy-dell's Hyprland over Tailscale)"

# Client half of the "RDP into another Omarchy box" setup. The SERVER half —
# the hypr-rdp server that this connects to — is migration 0000000021, which must
# run on omarchy-dell itself. Together they give a full-fidelity, H.264-streamed
# view of omarchy-dell's live Hyprland desktop.
#
#   omarchy-asus (this, client)  --RDP/Tailscale-->  omarchy-dell (hypr-rdp server)
#
# omarchy-dell tailnet node = 100.116.131.117 (MagicDNS: omarchy-dell.tailb12dd.ts.net),
# local user "melk". See docs/2026-07-28-rdp-into-omarchy-dell.md for the design.

# 1. RDP client — provides the `xfreerdp3` binary (already present on omarchy-asus).
if ! pacman -Q freerdp &>/dev/null; then
  echo "Installing freerdp..."
  sudo pacman -S --noconfirm --needed freerdp
else
  echo "freerdp already installed"
fi

# 2. Install the `omarchy-dell` command on PATH. Kept in ~/.local/bin (like
#    omarchy-fw16-windows) so it survives Omarchy updates/reinstalls.
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/omarchy-dell" <<'CMD'
#!/bin/bash

# RDP into omarchy-dell — its live Hyprland desktop — over Tailscale.
# Server side is hypr-rdp (migration 0000000021) listening on the dell's tailnet
# IP :3389. This streams the real omarchy-dell session (theme, waybar, wallpaper,
# whatever is running) as hardware-encoded H.264 — "as full a visual Omarchy as
# possible".
#
#   omarchy-dell                 connect fullscreen over Tailscale (works anywhere)
#   omarchy-dell --lan           force the home-LAN IP instead of the tailnet IP
#   omarchy-dell --windowed      open in a resizable window instead of fullscreen
#   omarchy-dell -- <args>       everything after -- passes through to xfreerdp3
#   DELL_USER=melk omarchy-dell  override the remote username for one run
#
# Fullscreen toggle while connected: Ctrl+Alt+Enter.
#
# One-time password setup (must match the password hypr-rdp runs with on the dell):
#   secret-tool store --label="omarchy-dell RDP" service omarchy-dell
# Re-run to change it. Clear it with:  secret-tool clear service omarchy-dell

set -euo pipefail

# --- edit these if needed ---------------------------------------------------
USER_DEFAULT="melk"                          # omarchy-dell local account
HOST_TS="100.116.131.117"                    # omarchy-dell tailnet IP (works anywhere)
HOST_LAN="192.168.68.51"                     # home LAN IP (fallback for --lan)
SCALE="100"                                  # HiDPI scaling: 100 / 140 / 180
GFX="AVC444"                                 # H.264 mode: AVC444 (best) / AVC420 / RFX
SECRET_SERVICE="omarchy-dell"                # gnome-keyring entry holding the RDP password
# ---------------------------------------------------------------------------
# MagicDNS name (if Tailscale DNS is healthy): omarchy-dell.tailb12dd.ts.net

USER_NAME="${DELL_USER:-$USER_DEFAULT}"
HOST="$HOST_TS"
FULLSCREEN="/f"

# Parse our own flags; collect the rest for xfreerdp3 (everything after -- too).
EXTRA=()
passthrough=0
for a in "$@"; do
  if [ "$passthrough" -eq 1 ]; then EXTRA+=("$a"); continue; fi
  case "$a" in
    --lan)      HOST="$HOST_LAN" ;;
    --windowed) FULLSCREEN="" ;;
    --)         passthrough=1 ;;
    *)          EXTRA+=("$a") ;;
  esac
done

# Pull the saved password from the keyring so nothing is ever prompted on a TTY.
PW_ARG=()
if PW=$(secret-tool lookup service "$SECRET_SERVICE" 2>/dev/null) && [ -n "$PW" ]; then
  PW_ARG=(/p:"$PW")
else
  echo "!! No saved password. Run once:  secret-tool store --label=\"omarchy-dell RDP\" service $SECRET_SERVICE" >&2
fi

echo ">> connecting to omarchy-dell ($HOST) as $USER_NAME"

# Once the FreeRDP window maps, focus + fullscreen it in Hyprland. FreeRDP only
# grabs the keyboard (forwarding ALL keys, incl. SUPER, to the remote) when its
# window is focused; a tiled/unfocused window leaks every keystroke to the local
# compositor. Skipped with --windowed. Release the grab in-session with Right CTRL.
if [ -n "$FULLSCREEN" ] && command -v hyprctl >/dev/null 2>&1; then
  ( for _ in $(seq 1 40); do
      addr=$(hyprctl clients 2>/dev/null | awk -v h="FreeRDP: $HOST" '$0 ~ ("^Window .* -> " h) {print $2; exit}')
      if [ -n "$addr" ]; then
        hyprctl dispatch focuswindow address:0x"$addr" >/dev/null 2>&1
        hyprctl dispatch fullscreen 0 >/dev/null 2>&1
        break
      fi
      sleep 0.25
    done ) &
fi

# Capture output so we can tell a genuine failure from a normal close. This FreeRDP
# build raises SIGABRT on teardown even on success, so the exit code is unreliable —
# decide from the actual error text in the log, not from $?.
LOG=$(mktemp -t dell-rdp.XXXXXX)
set +e
xfreerdp3 \
  /v:"$HOST" \
  /u:"$USER_NAME" \
  "${PW_ARG[@]}" \
  /cert:ignore \
  /scale:"$SCALE" \
  /gfx:"$GFX" \
  /dynamic-resolution \
  /sound \
  /microphone \
  +clipboard \
  /network:lan \
  +auto-reconnect \
  /auto-reconnect-max-retries:50 \
  ${FULLSCREEN:+$FULLSCREEN} \
  "${EXTRA[@]}" 2>&1 | tee "$LOG"
set -e

# Only warn on real auth/connection errors — never on a normal window close.
store_cmd="secret-tool store --label=\"omarchy-dell RDP\" service $SECRET_SERVICE"
notify() { command -v notify-send >/dev/null 2>&1 && notify-send -u critical "omarchy-dell RDP failed" "$1"; echo "$1" >&2; }

if [ "${#PW_ARG[@]}" -eq 0 ]; then
  notify "No saved password. Store it once: $store_cmd"
elif grep -qiE "LOGON_FAILURE|AUTHENTICATION_FAILED|ACCESS_DENIED" "$LOG"; then
  notify "Login rejected — check the password matches hypr-rdp on the dell. Re-store: $store_cmd"
elif grep -qiE "ERRCONNECT_(CONNECT|DNS|TCP|TLS)|failed to connect|unable to connect|Name or service not known" "$LOG"; then
  notify "Could not reach $HOST — is omarchy-dell online, Tailscale up, and hypr-rdp running? On home wifi try: omarchy-dell --lan"
fi

rm -f "$LOG"
CMD
chmod +x "$HOME/.local/bin/omarchy-dell"

# 3. Short `dell` alias for convenience
ln -sf omarchy-dell "$HOME/.local/bin/dell"

# 4. Desktop launcher so it shows up in Walker (Super+Space). No terminal needed:
#    cert auto-accepted (/cert:ignore) and password from the keyring, so xfreerdp3
#    opens the RDP window directly. Absolute path because Walker launches via
#    uwsm-app, whose session PATH does NOT include ~/.local/bin.
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/omarchy-dell.desktop" <<DESKTOP
[Desktop Entry]
Name=omarchy-dell (RDP)
Comment=Remote desktop into omarchy-dell's Hyprland over Tailscale (hypr-rdp)
Exec=uwsm-app -- $HOME/.local/bin/omarchy-dell
Icon=preferences-desktop-remote-desktop
Type=Application
Categories=Network;RemoteAccess;
Keywords=rdp;remote;omarchy;dell;hyprland;xfreerdp;tailscale;
Terminal=false
StartupNotify=true
DESKTOP
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# 5. One manual step that CANNOT live in a migration: the RDP password must be
#    typed interactively into the keyring, and must match hypr-rdp on the dell.
if secret-tool lookup service omarchy-dell >/dev/null 2>&1; then
  echo "✓ Installed. omarchy-dell RDP password already saved in the keyring."
else
  echo "✓ Installed — but ONE manual step remains (see docs/current/local-setup.md):"
  echo "    secret-tool store --label=\"omarchy-dell RDP\" service omarchy-dell"
  echo "  (use the same password hypr-rdp runs with on omarchy-dell)"
fi
echo "Run: omarchy-dell (or: dell), or launch 'omarchy-dell (RDP)' from Super+Space"
