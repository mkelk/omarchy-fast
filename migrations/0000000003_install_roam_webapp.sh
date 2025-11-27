echo "Install Roam Research web app"

DESKTOP_FILE="$HOME/.local/share/applications/roam-research.desktop"

if [ ! -f "$DESKTOP_FILE" ]; then
  mkdir -p "$HOME/.local/share/applications"

  cat > "$DESKTOP_FILE" << 'INNER_EOF'
[Desktop Entry]
Name=Roam Research
Comment=Note-taking tool for networked thought
Exec=omarchy-launch-webapp "https://roamresearch.com/#/app/MelkGeneral"
Icon=text-editor
Type=Application
Categories=Office;Education;
StartupWMClass=roamresearch.com__app
INNER_EOF

fi
