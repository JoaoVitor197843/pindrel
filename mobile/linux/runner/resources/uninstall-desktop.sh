#!/bin/sh
# Undoes install-desktop.sh: removes Pindrel from the application menu of the current user.
# The notes and settings stay unless --purge is given (the app's own "Apagar todos os dados" does the same from inside).
# The bundle folder itself is not touched: delete it by hand.
set -eu
data="${XDG_DATA_HOME:-$HOME/.local/share}"
purge=0
for arg in "$@"; do
  case "$arg" in
    --purge) purge=1 ;;
    -h|--help)
      echo "uso: uninstall-desktop.sh [--purge]"
      echo "  sem opções: tira o Pindrel do menu de aplicativos e mantém suas notas"
      echo "  --purge:    também apaga as notas e os dados do app neste aparelho"
      exit 0 ;;
    *) echo "opção desconhecida: $arg" >&2; exit 2 ;;
  esac
done

rm -f "$data/applications/com.pindrel.app.desktop" "$data/icons/hicolor/512x512/apps/com.pindrel.app.png"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$data/applications" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$data/icons/hicolor" || true
echo "Pindrel removido do menu de aplicativos."

if [ "$purge" = 1 ]; then
  # path_provider keeps the app's data in a folder named after the application id
  dir="$data/com.pindrel.app"
  if [ -d "$dir" ]; then
    rm -rf -- "$dir"
    echo "Dados do app apagados: $dir"
  else
    echo "Nenhum dado do app encontrado em $dir"
  fi
  # the session and paired servers live in the keyring (libsecret), when there is one
  if command -v secret-tool >/dev/null 2>&1; then
    secret-tool clear account com.pindrel.app.secureStorage >/dev/null 2>&1 || true
  else
    echo "Aviso: sem secret-tool, o que o app guardou no chaveiro do sistema (sessão, servidores) não foi apagado."
  fi
else
  echo "Suas notas foram mantidas. Para apagá-las também: $0 --purge"
fi
