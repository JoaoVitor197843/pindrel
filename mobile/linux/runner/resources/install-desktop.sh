#!/bin/sh
# Adds Pindrel to the application menu of the current user (no root needed).
# Run it from the unpacked bundle; moving the folder afterwards means running it again.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/512x512/apps"
mkdir -p "$apps" "$icons"
cp "$here/data/com.pindrel.app.png" "$icons/com.pindrel.app.png"
sed "s|@EXEC@|$here/Pindrel|" "$here/data/com.pindrel.app.desktop" > "$apps/com.pindrel.app.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$apps" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" || true
echo "Pindrel adicionado ao menu de aplicativos."
