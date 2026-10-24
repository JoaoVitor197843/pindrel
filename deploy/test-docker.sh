#!/bin/sh
# Brings Plany up in Docker for local testing: Postgres + 2 API replicas + gateway (compose.yml + compose.lb.yml).
#   sh deploy/test-docker.sh              rebuilds and starts (the default)
#   sh deploy/test-docker.sh up [N]       same, with N replicas (default 2)
#   sh deploy/test-docker.sh reset        tears down, wipes the database (volumes) and starts again
#   sh deploy/test-docker.sh down         tears down (the database stays)
#   sh deploy/test-docker.sh status       containers, port and servers found on the network
#   sh deploy/test-docker.sh logs [svc]   follows the logs (all, or one service: gateway, plany, postgres)
# The port comes from PORT in .env (or 8080). For tests only: it does not use the registry nor update.sh.
set -eu
cd "$(dirname "$0")/.."

compose() { docker compose -f compose.yml -f compose.lb.yml "$@"; }

port() {
  p=${PORT:-}
  if [ -z "$p" ] && [ -f .env ]; then p=$(sed -n 's/^PORT=//p' .env | head -n 1); fi
  echo "${p:-8080}"
}

up() {
  compose up -d --build --scale "plany=${1:-2}"
  p=$(port)
  printf 'aguardando o gateway'
  for _ in $(seq 1 60); do
    if curl -fsS -o /dev/null -m 2 "http://127.0.0.1:$p/server/info/" 2>/dev/null; then
      echo " ok"
      echo "web/API: http://localhost:$p/"
      if [ "$(systemctl is-active ufw 2>/dev/null)" = active ] && ! grep -q "dport $p -j ACCEPT" /etc/ufw/user.rules 2>/dev/null; then
        echo "aviso: o ufw está ativo; para o celular alcançar, libere a porta: sudo ufw allow $p/tcp"
      fi
      return 0
    fi
    printf .
    sleep 2
  done
  echo
  echo "o gateway não respondeu em 2 min; veja: sh deploy/test-docker.sh logs gateway" >&2
  return 1
}

case "${1:-up}" in
  up) shift 2>/dev/null || true; up "$@" ;;
  reset) compose down -v; up ;;
  down) compose down ;;
  status)
    compose ps
    curl -fsS -m 3 "http://127.0.0.1:$(port)/server/discover/" 2>/dev/null | strings || echo "(gateway não respondeu)"
    ;;
  logs) shift; compose logs -f --tail 50 "$@" ;;
  *) sed -n '2,11p' "$0"; exit 2 ;;
esac
