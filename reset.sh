#!/bin/bash
set -eEo pipefail

echo "🔄 Omarchy-fast Reset & Re-setup"
echo "================================"
echo ""
echo "This will:"
echo "  1. Remove your custom migrations from Omarchy"
echo "  2. Clear migration state (so they run again)"
echo "  3. Re-run setup.sh to reinstall migrations"
echo ""

if ! command -v gum &> /dev/null; then
    read -p "Are you sure? (y/N) " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0
else
    gum confirm "Are you sure you want to reset and re-setup?" || exit 0
fi

echo ""
echo "🗑️  Removing custom migrations from Omarchy..."
# Remove migrations that came from omarchy-fast (match our migration files)
for migration in migrations/*.sh; do
    if [[ -f "$migration" ]]; then
        name=$(basename "$migration" | sed 's/^[0-9]*_//')
        # Remove from Omarchy migrations dir
        rm -f ~/.local/share/omarchy/migrations/*_"$name"
        # Remove state marker
        rm -f ~/.local/state/omarchy/migrations/*_"$name"
        echo "   Removed: $name"
    fi
done

echo ""
echo "🔧 Re-running setup..."
./setup.sh

echo ""
echo "✅ Reset complete!"
echo ""
echo "Run 'omarchy-migrate' to apply your migrations."
