echo "Install Tailscale VPN with SSH access and exit node"

if ! pacman -Q tailscale &>/dev/null; then
  sudo pacman -S --noconfirm --needed tailscale
fi

# Enable the tailscaled service
if ! systemctl is-enabled tailscaled &>/dev/null; then
  sudo systemctl enable --now tailscaled
fi

# Enable IP forwarding so this machine can route traffic as an exit node
# https://tailscale.com/kb/1019/subnets#enable-ip-forwarding
if [ ! -f /etc/sysctl.d/99-tailscale.conf ]; then
  echo "Enabling IP forwarding for exit node..."
  printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' \
    | sudo tee /etc/sysctl.d/99-tailscale.conf >/dev/null
  sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
fi

# Connect to Tailscale with SSH and exit node advertising enabled.
# --ssh allows SSH access from other devices on your tailnet.
# --advertise-exit-node offers this machine as an exit node (route all traffic).
if ! tailscale status &>/dev/null; then
  echo "Connecting to Tailscale with SSH and exit node enabled..."
  sudo tailscale up --ssh --advertise-exit-node
else
  # Already connected, ensure SSH and exit node are enabled
  echo "Enabling Tailscale SSH and exit node..."
  sudo tailscale set --ssh --advertise-exit-node
fi

echo "Tailscale SSH is now enabled. Connect from other tailnet devices with:"
echo "  ssh $(whoami)@$(hostname)"
echo ""
echo "This machine is now advertising as an exit node."
echo "IMPORTANT: Approve it in the admin console before it can be used:"
echo "  https://login.tailscale.com/admin/machines"
echo "Then on another device: tailscale set --exit-node=$(hostname)"
