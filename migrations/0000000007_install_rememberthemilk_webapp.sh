echo "Install Remember The Milk web app"

DESKTOP_FILE="$HOME/.local/share/applications/rememberthemilk.desktop"

if [ ! -f "$DESKTOP_FILE" ]; then
  mkdir -p "$HOME/.local/share/applications"

  cat > "$DESKTOP_FILE" << 'INNER_EOF'
[Desktop Entry]
Name=Remember The Milk
Comment=Task management and to-do lists
Exec=omarchy-launch-webapp "https://www.rememberthemilk.com/app/#list/41300145"
Icon=task-due
Type=Application
Categories=Office;Productivity;
StartupWMClass=www.rememberthemilk.com
INNER_EOF

fi
