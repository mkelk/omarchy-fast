#!/bin/bash
set -eEo pipefail

REPO_URL="https://github.com/mkelk/omarchy-fast.git"
INSTALL_DIR="$HOME/omarchy-fast"

echo "🚀 Omarchy Fast-Start Bootstrap"
echo "==============================="
echo ""

# Check if Omarchy is installed
if [ ! -d "$HOME/.local/share/omarchy" ]; then
    echo "❌ Error: Omarchy is not installed"
    echo "Please install Omarchy first: https://omarchy.org"
    exit 1
fi

echo "✓ Omarchy installation found"

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "❌ Error: git is not installed"
    echo "Please install git first: sudo pacman -S git"
    exit 1
fi

echo "✓ Git is installed"
echo ""

# Clone or update the repository
if [ -d "$INSTALL_DIR" ]; then
    echo "📦 Repository already exists at $INSTALL_DIR"
    echo "Pulling latest changes..."
    cd "$INSTALL_DIR"
    git pull
else
    echo "📦 Cloning repository..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

echo ""
echo "✓ Repository ready"
echo ""

# Run the setup script
echo "🔧 Running setup..."
./setup.sh

echo ""
echo "🎉 Bootstrap complete!"
echo ""
echo "Your omarchy-fast setup is ready at: $INSTALL_DIR"
echo ""
