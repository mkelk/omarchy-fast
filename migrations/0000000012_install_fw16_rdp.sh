#!/bin/bash
set -eEo pipefail

echo "melk: Install FreeRDP + omarchy-fw16-windows command (RDP into the FW16 Windows boot over Tailscale)"

# The FW16 is a dual-boot laptop with two separate tailnet identities:
#   - Linux boot   = node "fw16" (the Omarchy side)
#   - Windows boot = node "win-fw16" (was DESKTOP-CJJNNGR), local user "morten"  <- what we RDP into
# Ref: sst1-homelab docs (fw16 / fw16-windows).

# 1. RDP client — provides the `xfreerdp3` binary
if ! pacman -Q freerdp &>/dev/null; then
  echo "Installing freerdp..."
  sudo pacman -S --noconfirm --needed freerdp
else
  echo "freerdp already installed"
fi

# 2. Install the `omarchy-fw16-windows` command on PATH (tab-completes alongside omarchy-* commands).
#    Kept in ~/.local/bin rather than Omarchy's own bin/ so it survives Omarchy updates/reinstalls.
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/omarchy-fw16-windows" <<'CMD'
#!/bin/bash

# RDP into the Framework 16 — WINDOWS boot — over Tailscale.
# The FW16 is a dual-boot laptop with two separate tailnet identities:
#   - Linux boot  = node "fw16" (100.106.142.23)   <- the Omarchy side, NOT this
#   - Windows boot = node "win-fw16" (was DESKTOP-CJJNNGR)  <- this command connects here
# BitLocker C:, local user "morten". Ref: sst1-homelab docs fw16 / fw16-windows.
#
#   omarchy-fw16-windows                      connect over Tailscale (works anywhere)
#   omarchy-fw16-windows --lan                force the home-LAN IP instead
#   omarchy-fw16-windows -f                   extra args pass through to xfreerdp3 (fullscreen)
#   FW16_USER=morten omarchy-fw16-windows     override the username for one run
#
# One-time password setup (so it never prompts / needs a terminal):
#   secret-tool store --label="FW16 Windows RDP" service fw16-windows
# Re-run that to change the saved password. Clear it with:
#   secret-tool clear service fw16-windows

set -euo pipefail

# --- edit these if needed ---------------------------------------------------
USER_DEFAULT="morten"                        # FW16 Windows local account
DOMAIN=""                                    # empty = LOCAL account; "MicrosoftAccount" for an MS-account login
HOST_TS="win-fw16.tailb12dd.ts.net"          # FW16 Windows tailnet node (MagicDNS) — works anywhere
HOST_LAN="192.168.68.57"                     # home LAN IP (fallback)
SCALE="180"                                  # HiDPI scaling: 100 / 140 / 180 (higher = bigger UI)
SECRET_SERVICE="fw16-windows"                # gnome-keyring entry holding the Windows password
# ---------------------------------------------------------------------------

USER_NAME="${FW16_USER:-$USER_DEFAULT}"
HOST="$HOST_TS"

# --lan forces the local address; strip it from the args passed to xfreerdp3
EXTRA=()
for a in "$@"; do
  case "$a" in
    --lan) HOST="$HOST_LAN" ;;
    *) EXTRA+=("$a") ;;
  esac
done

DOM_ARG=()
[ -n "$DOMAIN" ] && DOM_ARG=(/d:"$DOMAIN")

# Pull the saved password from the keyring so nothing is ever prompted on a TTY.
# (Without this the command would fall back to interactive prompts and need a terminal.)
PW_ARG=()
if PW=$(secret-tool lookup service "$SECRET_SERVICE" 2>/dev/null) && [ -n "$PW" ]; then
  PW_ARG=(/p:"$PW")
else
  echo "!! No saved password. Run once:  secret-tool store --label=\"FW16 Windows RDP\" service $SECRET_SERVICE" >&2
fi

echo ">> connecting to FW16 Windows ($HOST) as ${DOMAIN:+$DOMAIN\\}$USER_NAME"

# Capture output so we can tell a genuine failure from a normal close. This FreeRDP
# build raises SIGABRT on teardown even on success, so the exit code is unreliable —
# decide from the actual error text in the log, not from $?.
LOG=$(mktemp -t fw16-rdp.XXXXXX)
set +e
xfreerdp3 \
  /v:"$HOST" \
  "${DOM_ARG[@]}" \
  /u:"$USER_NAME" \
  "${PW_ARG[@]}" \
  /cert:ignore \
  /scale:"$SCALE" \
  /dynamic-resolution \
  +auto-reconnect \
  /auto-reconnect-max-retries:50 \
  +clipboard \
  /sound \
  "${EXTRA[@]}" 2>&1 | tee "$LOG"
set -e

# Only warn on real auth/connection errors — never on a normal window close or a
# signal kill, which used to cry wolf.
store_cmd="secret-tool store --label=\"FW16 Windows RDP\" service $SECRET_SERVICE"
notify() { command -v notify-send >/dev/null 2>&1 && notify-send -u critical "FW16 Windows RDP failed" "$1"; echo "$1" >&2; }

if [ "${#PW_ARG[@]}" -eq 0 ]; then
  notify "No saved password. Store it once: $store_cmd"
elif grep -qiE "LOGON_FAILURE|AUTHENTICATION_FAILED|ACCESS_DENIED" "$LOG"; then
  notify "Login rejected (wrong username or password). Re-store it: $store_cmd"
elif grep -qiE "ERRCONNECT_(CONNECT|DNS|TCP|TLS)|failed to connect|unable to connect|Name or service not known" "$LOG"; then
  notify "Could not reach $HOST — is win-fw16 online and Tailscale up? On home wifi try: fw16-win --lan"
fi

rm -f "$LOG"
CMD
chmod +x "$HOME/.local/bin/omarchy-fw16-windows"

# 3. Short `fw16-win` alias for convenience
ln -sf omarchy-fw16-windows "$HOME/.local/bin/fw16-win"

# 4. Desktop launcher so it shows up in Walker (Super+Space). No terminal needed:
#    the cert is auto-accepted (/cert:ignore) and the password comes from the keyring,
#    so xfreerdp3 opens the RDP window directly with no interactive prompts.
#    Absolute path to the command: Walker launches via uwsm-app, whose session PATH
#    does NOT include ~/.local/bin, so referencing it by bare name fails to launch.
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/omarchy-fw16-windows.desktop" <<DESKTOP
[Desktop Entry]
Name=Framework 16 — Windows (RDP)
Comment=Remote desktop into the FW16 Windows boot (win-fw16) over Tailscale
Exec=uwsm-app -- $HOME/.local/bin/omarchy-fw16-windows
Icon=preferences-desktop-remote-desktop
Type=Application
Categories=Network;RemoteAccess;
Keywords=rdp;remote;windows;framework;fw16;xfreerdp;tailscale;
Terminal=false
StartupNotify=true
DESKTOP
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# 5. One manual step that CANNOT live in a migration: the Windows password must be
#    typed interactively into the keyring. Flag it clearly (see docs/current/local-setup.md).
if secret-tool lookup service fw16-windows >/dev/null 2>&1; then
  echo "✓ Installed. Windows password already saved in the keyring."
else
  echo "✓ Installed — but ONE manual step remains (see docs/current/local-setup.md):"
  echo "    secret-tool store --label=\"FW16 Windows RDP\" service fw16-windows"
  echo "  Until then the launcher will show a 'login failed / no password' notification."
fi
echo "Run: omarchy-fw16-windows (or: fw16-win), or launch 'Framework 16 — Windows (RDP)' from Super+Space"
