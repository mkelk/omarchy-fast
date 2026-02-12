echo "Install Tailscale VPN with SSH access"

if ! pacman -Q tailscale &>/dev/null; then
  sudo pacman -S --noconfirm --needed tailscale
fi

# Enable the tailscaled service
if ! systemctl is-enabled tailscaled &>/dev/null; then
  sudo systemctl enable --now tailscaled
fi

# Connect to Tailscale with SSH enabled
# This allows SSH access from other devices on your tailnet
if ! tailscale status &>/dev/null; then
  echo "Connecting to Tailscale with SSH enabled..."
  sudo tailscale up --ssh
else
  # Already connected, ensure SSH is enabled
  echo "Enabling Tailscale SSH..."
  sudo tailscale set --ssh
fi

echo "Tailscale SSH is now enabled. Connect from other tailnet devices with:"
echo "  ssh $(whoami)@$(hostname)"
