#!/bin/bash
set -eEo pipefail

echo "melk: Install pCloud Drive"

# Check if pcloud-drive is already installed
if ! command -v pcloud &>/dev/null; then
  echo "Installing pCloud Drive from AUR..."
  if ! yay -Sy --noconfirm pcloud-drive; then
    echo "Failed to install pCloud Drive"
    exit 1
  fi
  # Update locate database like omarchy-pkg-aur-install does
  sudo updatedb
else
  echo "pCloud Drive already installed"
fi

echo "✓ pCloud Drive installation complete"
