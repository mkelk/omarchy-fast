echo "Install herdr"

if ! pacman -Q herdr-bin &>/dev/null; then
  yay -S --noconfirm --needed herdr-bin
fi
