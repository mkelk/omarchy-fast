echo "Install Cursor IDE"

if ! pacman -Q cursor-bin &>/dev/null; then
  yay -S --noconfirm --needed cursor-bin
fi
