#!/bin/bash
set -eEo pipefail

echo "melk: Install Android Studio"

# Check if android-studio is already installed
if ! command -v android-studio &>/dev/null; then
  echo "Installing Android Studio from AUR..."
  if ! yay -Sy --noconfirm android-studio; then
    echo "Failed to install Android Studio"
    exit 1
  fi
  # Update locate database like omarchy-pkg-aur-install does
  sudo updatedb
else
  echo "Android Studio already installed"
fi

echo "✓ Android Studio installation complete"
