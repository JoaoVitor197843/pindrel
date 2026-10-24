#!/bin/sh
# Installs the systemd timer that runs deploy/update.sh every minute.
#   sudo sh deploy/install-timer.sh            installs and enables (runs the update as the user who called sudo)
#   sh deploy/install-timer.sh --print         only prints the units, without installing
# The user must be in the `docker` group and have done `docker login` on the registry (see deploy/README.md).
set -eu
dir=$(cd "$(dirname "$0")/.." && pwd)
user=${SUDO_USER:-$(id -un)}

service() {
  cat <<UNIT
[Unit]
Description=Atualiza o Plany a partir do registry
Wants=network-online.target docker.service
After=network-online.target docker.service

[Service]
Type=oneshot
User=$user
WorkingDirectory=$dir
ExecStart=$dir/deploy/update.sh
# the timer fires again in 1 min (flock keeps the runs apart); a stuck update cannot hang around forever
TimeoutStartSec=15min
UNIT
}

timer() {
  cat <<UNIT
[Unit]
Description=Procura uma versão nova do Plany

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
RandomizedDelaySec=30
Persistent=true

[Install]
WantedBy=timers.target
UNIT
}

if [ "${1:-}" = --print ]; then
  echo "# plany-update.service"; service; echo; echo "# plany-update.timer"; timer
  exit 0
fi

[ "$(id -u)" = 0 ] || { echo "rode com sudo" >&2; exit 1; }
service >/etc/systemd/system/plany-update.service
timer >/etc/systemd/system/plany-update.timer
systemctl daemon-reload
systemctl enable --now plany-update.timer
systemctl list-timers plany-update.timer --no-pager
