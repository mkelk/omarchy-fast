#!/bin/bash
set -eEo pipefail

echo "melk: Neovim — vim-be-good (motion/edit practice game)"

# ThePrimeagen/vim-be-good: interactive training games for core vim motions
# (relative jumps, ciw, deletion targets). Part of the LazyVim learning path
# in the vault's Tech/LazyVim note. Start a session with :VimBeGood.

PLUGIN_DIR="$HOME/.config/nvim/lua/plugins"
PLUGIN_FILE="$PLUGIN_DIR/vim-be-good.lua"

if [ ! -d "$PLUGIN_DIR" ]; then
  echo "!! $PLUGIN_DIR not found — LazyVim/Omarchy nvim config missing here. Skipping."
  exit 0
fi

cat > "$PLUGIN_FILE" <<'EOF'
return {
  "ThePrimeagen/vim-be-good",
}
EOF
echo "✓ Wrote $PLUGIN_FILE"

if command -v nvim >/dev/null; then
  nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 && echo "✓ Lazy sync complete." \
    || echo "!! Lazy sync skipped/failed — will install on next nvim launch."
fi

echo "Migration completed successfully!"
