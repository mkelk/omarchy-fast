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

# Find the highest timestamp in Omarchy migrations
echo "Detecting latest Omarchy migration..."
highest_timestamp=0
if [ -d "$MIGRATIONS_TARGET" ]; then
    for existing in "$MIGRATIONS_TARGET"/*.sh; do
        if [ -f "$existing" ]; then
            filename=$(basename "$existing")
            # Extract timestamp (first part before _ or .sh)
            timestamp=$(echo "$filename" | sed 's/[^0-9].*//')
            if [ -n "$timestamp" ] && [ "$timestamp" -gt "$highest_timestamp" ]; then
                highest_timestamp=$timestamp
            fi
        fi
    done
fi

if [ "$highest_timestamp" -gt 0 ]; then
    echo "✓ Latest Omarchy migration: $highest_timestamp"
else
    echo "✓ No existing migrations found, using current timestamp"
    highest_timestamp=$(date +%s)
fi

echo ""

# Copy all migration files with new timestamps
echo "Installing custom migrations..."
migration_count=0
new_timestamp=$((highest_timestamp + 1))

for migration in "$MIGRATIONS_SOURCE"/*.sh; do
    if [ -f "$migration" ]; then
        migration_name=$(basename "$migration")
        # Extract description (everything after first _ or use filename)
        description=$(echo "$migration_name" | sed 's/^[0-9]*_//' | sed 's/\.sh$//')

        # Create new filename with incremented timestamp
        new_name="${new_timestamp}_${description}.sh"
        target_file="$MIGRATIONS_TARGET/$new_name"

        # Skip if a migration with this description already exists (any timestamp)
        if ls "$MIGRATIONS_TARGET"/*"_${description}.sh" 2>/dev/null | grep -q .; then
            echo "  ⊘ $description (already exists)"
        else
            # Copy migration with new timestamp
            cp "$migration" "$target_file"
            chmod +x "$target_file"
            echo "  → $new_name"
            ((migration_count++))
        fi

        # Increment for next migration
        ((new_timestamp++))
    fi
done

echo ""
echo "✅ Setup complete!"
echo "   Installed $migration_count new migration(s)"
echo ""
echo "Next steps:"
echo "  1. Run migrations with: omarchy-migrate"
echo "  2. To add more migrations, edit files in: $MIGRATIONS_SOURCE"
echo "  3. Re-run this setup script to install new migrations"
echo ""
