#!/bin/sh
# Instala o timer do systemd que roda deploy/update.sh a cada 5 minutos.
#   sudo sh deploy/install-timer.sh            instala e liga (roda o update como o usuário que chamou o sudo)
#   sh deploy/install-timer.sh --print         só mostra as units, sem instalar
# O usuário precisa estar no grupo `docker` e ter feito `docker login` no registry (ver deploy/README.md).
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
# o timer dispara de novo em 5 min; um update travado não pode ficar para sempre
TimeoutStartSec=15min
UNIT
}

timer() {
  cat <<UNIT
[Unit]
Description=Procura uma versão nova do Plany

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
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
