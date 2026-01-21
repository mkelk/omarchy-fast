echo "Install Warp Terminal"

if ! pacman -Q warp-terminal-bin &>/dev/null; then
  yay -S --noconfirm --needed warp-terminal-bin
fi
