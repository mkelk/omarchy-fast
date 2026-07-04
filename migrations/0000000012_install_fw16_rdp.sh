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

set -euo pipefail

# --- edit these if needed ---------------------------------------------------
USER_DEFAULT="morten"                        # FW16 Windows local account
DOMAIN=""                                    # empty = LOCAL account; "MicrosoftAccount" for an MS-account login
HOST_TS="win-fw16.tailb12dd.ts.net"          # FW16 Windows tailnet node (MagicDNS) — works anywhere
HOST_LAN="192.168.68.57"                     # home LAN IP (fallback)
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

echo ">> connecting to FW16 Windows ($HOST) as ${DOMAIN:+$DOMAIN\\}$USER_NAME"
exec xfreerdp3 \
  /v:"$HOST" \
  "${DOM_ARG[@]}" \
  /u:"$USER_NAME" \
  /dynamic-resolution \
  +clipboard \
  /sound \
  "${EXTRA[@]}"
CMD
chmod +x "$HOME/.local/bin/omarchy-fw16-windows"

# 3. Short `fw16-win` alias for convenience
ln -sf omarchy-fw16-windows "$HOME/.local/bin/fw16-win"

# 4. Desktop launcher so it shows up in Walker (Super+Space). Runs in a terminal
#    (via Omarchy's uwsm-app + xdg-terminal-exec) so the cert prompt and password work.
#    Absolute path to the command: Walker launches via uwsm-app, whose session PATH
#    does NOT include ~/.local/bin, so referencing it by bare name fails to launch.
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/omarchy-fw16-windows.desktop" <<DESKTOP
[Desktop Entry]
Name=Framework 16 — Windows (RDP)
Comment=Remote desktop into the FW16 Windows boot (win-fw16) over Tailscale
Exec=uwsm-app -- xdg-terminal-exec $HOME/.local/bin/omarchy-fw16-windows
Icon=preferences-desktop-remote-desktop
Type=Application
Categories=Network;RemoteAccess;
Keywords=rdp;remote;windows;framework;fw16;xfreerdp;tailscale;
Terminal=false
StartupNotify=true
DESKTOP
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

echo "✓ Installed. Run: omarchy-fw16-windows (or: fw16-win), or launch 'Framework 16 — Windows (RDP)' from Super+Space"
