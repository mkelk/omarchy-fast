#!/bin/bash
set -eEo pipefail

echo "melk: Install hypr-rdp server (native RDP into this machine's live Hyprland)"

# Server half of the "RDP into another Omarchy box" setup. Makes THIS machine
# reachable by an RDP client (the omarchy-dell command / migration 0000000020, or
# any FreeRDP / Windows RDP client) that connects to its tailnet IP :3389.
#
# hypr-rdp (https://github.com/MuNeNiCK/hypr-rdp) is a native RDP server for
# Hyprland: it captures the LIVE session and streams it as VA-API H.264, with
# PipeWire audio and clipboard sync — the fullest-fidelity "RDP into Omarchy".
#
# Safe to run on every machine: the autostart launcher self-gates on a keyring
# password (service "hypr-rdp"). A machine only actually serves once you store
# that password on it — so this daily-driver won't listen unless you opt it in.
# On omarchy-dell you DO want it; that's the intended target.
#
# See docs/2026-07-28-rdp-into-omarchy-dell.md for the full design + tradeoffs.

# --- 0. sanity: hypr-rdp needs Hyprland >= 0.54 -----------------------------
if command -v hyprctl >/dev/null 2>&1; then
  HVER=$(hyprctl version -j 2>/dev/null | grep -oE '"version": *"[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+' | head -1)
  if [ -n "$HVER" ]; then
    if ! awk -v v="$HVER" 'BEGIN{split(v,a,"."); exit !(a[1]>0 || (a[1]==0 && a[2]>=54))}'; then
      echo "⚠ Hyprland $HVER detected — hypr-rdp needs >= 0.54. Installing anyway; update Hyprland if capture fails."
    fi
  fi
fi

# --- 1. VA-API driver matching the GPU (for hardware H.264 encode) -----------
#     Without a driver hypr-rdp falls back to slower OpenH264 software encode.
GPU=$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' || true)
VA_PKGS=(libva-utils)
if echo "$GPU" | grep -qi 'intel'; then
  VA_PKGS+=(intel-media-driver)      # iHD, Gen8+ (CometLake etc.)
elif echo "$GPU" | grep -qiE 'amd|ati|radeon'; then
  VA_PKGS+=(libva-mesa-driver)
else
  VA_PKGS+=(libva-mesa-driver)       # sensible default
fi
echo "Installing VA-API driver(s): ${VA_PKGS[*]}"
sudo pacman -S --noconfirm --needed "${VA_PKGS[@]}"

# --- 2. hypr-rdp from the AUR + its runtime deps ----------------------------
sudo pacman -S --noconfirm --needed ffmpeg libva pipewire libxkbcommon libpulse
if ! pacman -Q hypr-rdp &>/dev/null; then
  echo "Building hypr-rdp from the AUR (Rust build — takes a few minutes)..."
  yay -S --noconfirm --needed hypr-rdp
else
  echo "hypr-rdp already installed"
fi

# --- 3. Launcher that reads the password from the keyring and binds to tailnet
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/omarchy-rdp-server" <<'CMD'
#!/bin/bash

# Start hypr-rdp against the current Hyprland session, bound to the Tailscale
# interface only (never 0.0.0.0 — the tailnet + password are the whole security
# model). Launched at login via ~/.config/hypr/autostart.conf; also runnable by
# hand from a terminal INSIDE the Hyprland session to (re)start it.
#
# Password comes from the login keyring:
#   secret-tool store --label="hypr-rdp server" service hypr-rdp
# No password stored => this machine simply doesn't serve (safe default).
#
# Tunables (env or edit): RDP_FPS, RDP_CODEC (auto|avc444|avc420),
# RDP_CAPTURE (wlr|ext), RDP_AUDIO (redirect|mirror|off), RDP_PORT.

set -uo pipefail

SECRET_SERVICE="hypr-rdp"
RDP_PORT="${RDP_PORT:-3389}"
RDP_FPS="${RDP_FPS:-60}"
RDP_CODEC="${RDP_CODEC:-auto}"
RDP_CAPTURE="${RDP_CAPTURE:-wlr}"     # switch to "ext" if capture fails on your Hyprland
RDP_AUDIO="${RDP_AUDIO:-redirect}"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-rdp.log"
mkdir -p "$(dirname "$LOG")"

# Need an RDP password, else don't serve.
PW=$(secret-tool lookup service "$SECRET_SERVICE" 2>/dev/null || true)
if [ -z "$PW" ]; then
  echo "$(date -Iseconds) no keyring password (service $SECRET_SERVICE) — not starting hypr-rdp" >>"$LOG"
  command -v notify-send >/dev/null 2>&1 && \
    notify-send "hypr-rdp not started" "No password stored. Run: secret-tool store --label=\"hypr-rdp server\" service hypr-rdp"
  exit 0
fi

# Bind to the Tailscale IP so it's only reachable over the tailnet.
TSIP=$(tailscale ip -4 2>/dev/null | head -1)
BIND="${TSIP:-127.0.0.1}:$RDP_PORT"

# Don't double-bind: stop any previous instance first.
pkill -x hypr-rdp 2>/dev/null || true
sleep 0.3

echo "$(date -Iseconds) starting hypr-rdp on $BIND (fps=$RDP_FPS codec=$RDP_CODEC capture=$RDP_CAPTURE)" >>"$LOG"
exec hypr-rdp \
  -u "$USER" \
  -p "$PW" \
  -b "$BIND" \
  --fps "$RDP_FPS" \
  --egfx-codec "$RDP_CODEC" \
  --capture-mode "$RDP_CAPTURE" \
  --audio-mode "$RDP_AUDIO" \
  >>"$LOG" 2>&1
CMD
chmod +x "$HOME/.local/bin/omarchy-rdp-server"

# --- 4. Autostart it with the Hyprland session (idempotent) -----------------
#     exec-once inherits the full Wayland/PipeWire env, which hypr-rdp needs.
AUTOSTART="$HOME/.config/hypr/autostart.conf"
MARKER="# omarchy-fast: hypr-rdp server"
mkdir -p "$(dirname "$AUTOSTART")"
touch "$AUTOSTART"
if ! grep -qF "$MARKER" "$AUTOSTART"; then
  {
    echo ""
    echo "$MARKER"
    echo "exec-once = ~/.local/bin/omarchy-rdp-server"
  } >> "$AUTOSTART"
  echo "Added hypr-rdp exec-once to $AUTOSTART"
  hyprctl reload >/dev/null 2>&1 || true
else
  echo "autostart entry already present"
fi

# --- 5. Flag the one manual step (keyring password) -------------------------
if secret-tool lookup service hypr-rdp >/dev/null 2>&1; then
  echo "✓ Installed and activated — hypr-rdp password is stored. Starting server now..."
  # Start immediately if we're inside a Hyprland session (otherwise it starts at next login).
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    setsid "$HOME/.local/bin/omarchy-rdp-server" >/dev/null 2>&1 &
    echo "  hypr-rdp launched (bound to $(tailscale ip -4 2>/dev/null | head -1):3389)."
  else
    echo "  Not inside a Hyprland session right now — it will start at next login."
  fi
else
  echo "✓ Installed — but this machine will NOT serve until you store a password (see docs/current/local-setup.md):"
  echo "    secret-tool store --label=\"hypr-rdp server\" service hypr-rdp"
  echo "  Then either log out/in, or run inside your Hyprland session:  omarchy-rdp-server &"
fi
echo "Clients connect to $(tailscale ip -4 2>/dev/null | head -1 || echo '<tailnet-ip>'):3389"
