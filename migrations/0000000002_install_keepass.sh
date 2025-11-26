echo "Install KeePassXC password manager"

if ! pacman -Q keepassxc &>/dev/null; then
  sudo pacman -S --noconfirm --needed keepassxc
fi
