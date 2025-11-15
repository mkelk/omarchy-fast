#!/bin/bash
set -eEo pipefail

OMARCHY_PATH="$HOME/.local/share/omarchy"
REPO_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_SOURCE="$REPO_PATH/migrations"
MIGRATIONS_TARGET="$OMARCHY_PATH/migrations"

echo "🚀 Omarchy Fast-Start Setup"
echo "=========================="
echo ""

# Check if Omarchy is installed
if [ ! -d "$OMARCHY_PATH" ]; then
    echo "❌ Error: Omarchy is not installed at $OMARCHY_PATH"
    echo "Please install Omarchy first: https://omarchy.org"
    exit 1
fi

echo "✓ Omarchy installation found at $OMARCHY_PATH"

# Create migrations directory if it doesn't exist
if [ ! -d "$MIGRATIONS_TARGET" ]; then
    echo "Creating migrations directory..."
    mkdir -p "$MIGRATIONS_TARGET"
fi

echo "✓ Migrations directory ready"
echo ""

# Symlink all migration files
echo "Symlinking custom migrations..."
migration_count=0

for migration in "$MIGRATIONS_SOURCE"/*.sh; do
    if [ -f "$migration" ]; then
        migration_name=$(basename "$migration")
        target_link="$MIGRATIONS_TARGET/$migration_name"

        # Remove existing symlink or file
        if [ -L "$target_link" ]; then
            rm "$target_link"
        elif [ -f "$target_link" ]; then
            echo "⚠ Warning: $migration_name already exists (not a symlink). Skipping."
            continue
        fi

        # Create symlink
        ln -s "$migration" "$target_link"
        echo "  → $migration_name"
        ((migration_count++))
    fi
done

echo ""
echo "✅ Setup complete!"
echo "   Symlinked $migration_count migration(s)"
echo ""
echo "Next steps:"
echo "  1. Review your migrations in: $MIGRATIONS_SOURCE"
echo "  2. Run migrations with: omarchy-migrate"
echo "  3. Edit migrations in this repo and re-run omarchy-migrate to apply changes"
echo ""
