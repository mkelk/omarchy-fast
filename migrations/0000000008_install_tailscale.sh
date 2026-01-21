echo "Install Tailscale VPN"

if ! pacman -Q tailscale &>/dev/null; then
  sudo pacman -S --noconfirm --needed tailscale
fi

# Enable the tailscaled service
if ! systemctl is-enabled tailscaled &>/dev/null; then
  sudo systemctl enable --now tailscaled
fi

echo "Run 'sudo tailscale up' to authenticate with your Tailscale account"
