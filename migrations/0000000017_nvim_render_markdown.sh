#!/bin/bash
set -eEo pipefail

echo "melk: Neovim — render-markdown.nvim (in-buffer markdown rendering)"

# Omarchy ships a LazyVim-based Neovim config in ~/.config/nvim. LazyVim loads
# any spec files under lua/plugins/, so we drop a self-contained plugin spec
# there for MeanderingProgrammer/render-markdown.nvim — the most popular
# in-buffer markdown renderer (headings, lists, code blocks, tables, checkboxes
# rendered live via Tree-sitter, raw markdown shown on the line being edited).
#
# Toggle at runtime with :RenderMarkdown toggle.

PLUGIN_DIR="$HOME/.config/nvim/lua/plugins"
PLUGIN_FILE="$PLUGIN_DIR/render-markdown.lua"

if [ ! -d "$PLUGIN_DIR" ]; then
  echo "!! $PLUGIN_DIR not found — LazyVim/Omarchy nvim config missing here. Skipping."
  exit 0
fi

cat > "$PLUGIN_FILE" <<'EOF'
return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  ft = { "markdown" },
  opts = {},
}
EOF
echo "✓ Wrote $PLUGIN_FILE"

# Install/update headlessly so it's ready on first real launch (no-op if nvim
# isn't on PATH — the plugin will install on next interactive start anyway).
if command -v nvim >/dev/null; then
  nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 && echo "✓ Lazy sync complete." \
    || echo "!! Lazy sync skipped/failed — will install on next nvim launch."
fi

echo "Migration completed successfully!"
