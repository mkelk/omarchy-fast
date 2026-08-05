#!/bin/bash
set -eEo pipefail

echo "melk: Install Microsoft core fonts incl. real Georgia (ttf-ms-fonts)"

# ── WHY ──────────────────────────────────────────────────────────────────────
# Client docs under Usenestor/…/ComputerCamp/_General are authored in Georgia.
# ttf-ms-fonts is Microsoft's "Core fonts for the Web" (corefonts): Arial, Times
# New Roman, Verdana, … and Georgia (georgia/b/i/z.ttf), installed under
# /usr/share/fonts. With the genuine face present LibreOffice resolves "Georgia"
# directly — no substitute font, no missing-font warning, exact rendering. So no
# fontconfig alias is needed: Georgia is matched by its own name.
#
# Carries Microsoft's EULA (custom:microsoft) — fine for personal use on your own
# machine. The build fetches the .exe bundles from corefonts.sourceforge.net, so it
# needs network at migration time. Needs sudo (package install), which
# omarchy-migrate provides. Idempotent: installs only if missing.

FONT_PKG="ttf-ms-fonts"

if pacman -Qi "$FONT_PKG" &>/dev/null; then
  echo "✓ $FONT_PKG already installed."
else
  echo "Installing $FONT_PKG from the AUR (downloads from SourceForge)…"
  yay -S --noconfirm --needed "$FONT_PKG"
  echo "✓ Installed $FONT_PKG."
fi

fc-cache -f &>/dev/null || true

echo "Verify:  fc-match Georgia   (expect Georgia.TTF)"
echo "Restart LibreOffice so it re-reads the font cache."
echo "Migration completed successfully!"
