#!/bin/sh
# Tests install-desktop.sh with bundle folders a person really has: spaces (the Portuguese desktop folder) and the
# characters the desktop entry spec makes special. Run: sh mobile/linux/runner/resources/test_install_desktop.sh
set -eu
src=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

check() { # folder name, expected Exec line
  bundle="$work/$1"
  mkdir -p "$bundle/data"
  cp "$src/install-desktop.sh" "$bundle/"
  cp "$src/com.pindrel.app.desktop" "$src/com.pindrel.app.png" "$bundle/data/"
  XDG_DATA_HOME="$work/share" sh "$bundle/install-desktop.sh" >/dev/null
  got=$(grep '^Exec=' "$work/share/applications/com.pindrel.app.desktop")
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1: $got (want $2)"; fails=$((fails + 1)); fi
  if command -v desktop-file-validate >/dev/null 2>&1 && ! desktop-file-validate "$work/share/applications/com.pindrel.app.desktop"; then
    echo "FAIL $1: desktop-file-validate"; fails=$((fails + 1))
  fi
}

check "pindrel" "Exec=\"$work/pindrel/Pindrel\""
check "Área de Trabalho/pindrel" "Exec=\"$work/Área de Trabalho/pindrel/Pindrel\""
check 'a"b$c%d&e|f\g' "Exec=\"$work/a\\\\\"b\\\\\$c%%d&e|f\\\\\\\\g/Pindrel\""
# the other lines are copied as they are
grep -q '^Name=Pindrel$' "$work/share/applications/com.pindrel.app.desktop" || { echo "FAIL other lines"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] && echo "todos os testes passaram" || { echo "$fails falharam"; exit 1; }
