echo "Install Slack web app"

DESKTOP_FILE="$HOME/.local/share/applications/slack.desktop"

if [ ! -f "$DESKTOP_FILE" ]; then
  mkdir -p "$HOME/.local/share/applications"

  cat > "$DESKTOP_FILE" << 'INNER_EOF'
[Desktop Entry]
Name=Slack
Comment=Team collaboration and messaging
Exec=omarchy-launch-webapp "https://app.slack.com/client/T042VJS4DUN/C04324JQ8MR"
Icon=slack
Type=Application
Categories=Network;InstantMessaging;
StartupWMClass=app.slack.com
INNER_EOF

fi
