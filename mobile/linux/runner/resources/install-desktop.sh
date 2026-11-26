#!/bin/sh
# Adds Pindrel to the application menu of the current user (no root needed).
# Run it from the unpacked bundle; moving the folder afterwards means running it again.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/512x512/apps"
mkdir -p "$apps" "$icons"
cp "$here/data/com.pindrel.app.png" "$icons/com.pindrel.app.png"
# Exec is split on spaces, so the path goes between double quotes, where \ " ` $ need a backslash; the value is a
# string of the desktop file too (every backslash doubled) and % is a field code (%%). A folder such as
# "~/Área de Trabalho/pindrel" used to make the entry run "~/Área" and open nothing.
exec_path=$(printf '%s' "$here/Pindrel" | sed -e 's/[\\"`$]/\\&/g' -e 's/\\/\\\\/g' -e 's/%/%%/g')
while IFS= read -r line || [ -n "$line" ]; do
  case $line in
    'Exec=@EXEC@') printf 'Exec="%s"\n' "$exec_path" ;;
    *) printf '%s\n' "$line" ;;
  esac
done < "$here/data/com.pindrel.app.desktop" > "$apps/com.pindrel.app.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$apps" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" || true
echo "Pindrel adicionado ao menu de aplicativos."
