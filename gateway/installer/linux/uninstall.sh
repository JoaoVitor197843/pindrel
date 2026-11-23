#!/bin/sh
# Undoes install.sh. Run it as root.
#   sudo ./uninstall.sh            removes the service and the program; keeps the settings and what the gateway learned
#   sudo ./uninstall.sh --purge    also removes /etc/pindrel-gateway, /var/lib/pindrel-gateway and the system user
# DESTDIR=<dir> works on a staged install (used by the tests).
set -eu

dest=${DESTDIR:-}
purge=0
for arg in "$@"; do
  case $arg in
    --purge) purge=1 ;;
    -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "opção desconhecida: $arg (veja --help)" >&2; exit 2 ;;
  esac
done
if [ -z "$dest" ] && [ "$(id -u)" -ne 0 ]; then
  echo "Rode como root: sudo $0" >&2
  exit 1
fi

if [ -z "$dest" ] && command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now pindrel-gateway 2>/dev/null || true
fi
rm -f "$dest/etc/systemd/system/pindrel-gateway.service" "$dest/usr/local/bin/pindrel-gateway"
if [ -z "$dest" ] && command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi
echo "Serviço e programa removidos."

if [ "$purge" = 1 ]; then
  rm -rf -- "$dest/etc/pindrel-gateway" "$dest/var/lib/pindrel-gateway"
  if [ -z "$dest" ] && id -u pindrel-gateway >/dev/null 2>&1; then
    userdel pindrel-gateway 2>/dev/null || true
  fi
  echo "Configuração, dados e usuário removidos."
else
  echo "Mantive /etc/pindrel-gateway e /var/lib/pindrel-gateway (para apagar: $0 --purge)."
fi
