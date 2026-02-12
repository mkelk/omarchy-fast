echo "Install tmux"

if ! pacman -Q tmux &>/dev/null; then
  sudo pacman -S --noconfirm --needed tmux
fi
