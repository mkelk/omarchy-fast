#!/bin/bash
set -eEo pipefail

echo "Installing Visual Studio Code..."

# Install VS Code from the official repository
# This assumes you're on an Arch-based system (like Omarchy)

# Check if yay (AUR helper) is available
if command -v yay &> /dev/null; then
    echo "Using yay to install visual-studio-code-bin..."
    yay -S --noconfirm visual-studio-code-bin
elif command -v paru &> /dev/null; then
    echo "Using paru to install visual-studio-code-bin..."
    paru -S --noconfirm visual-studio-code-bin
elif command -v pacman &> /dev/null; then
    echo "Installing code (OSS version) via pacman..."
    sudo pacman -S --noconfirm code
else
    echo "❌ No package manager found. Please install VS Code manually."
    exit 1
fi

echo "✅ VS Code installation complete!"

# Optional: Install common VS Code extensions
# Uncomment the extensions you want:
# code --install-extension ms-python.python
# code --install-extension dbaeumer.vscode-eslint
# code --install-extension esbenp.prettier-vscode
# code --install-extension ms-vscode.cpptools
# code --install-extension rust-lang.rust-analyzer

echo "Migration completed successfully!"
