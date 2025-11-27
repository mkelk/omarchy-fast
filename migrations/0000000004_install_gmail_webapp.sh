echo "Install Gmail web app"

DESKTOP_FILE="$HOME/.local/share/applications/gmail.desktop"

if [ ! -f "$DESKTOP_FILE" ]; then
  mkdir -p "$HOME/.local/share/applications"

  cat > "$DESKTOP_FILE" << 'INNER_EOF'
[Desktop Entry]
Name=Gmail
Comment=Google Mail
Exec=omarchy-launch-webapp "https://mail.google.com/mail/u/0/#inbox"
Icon=mail-client
Type=Application
Categories=Network;Email;
StartupWMClass=mail.google.com
INNER_EOF

fi
