#!/bin/sh
# Installs the Pindrel gateway as a systemd service. Run it as root from the unpacked release:
#   sudo ./install.sh                      asks the three questions (name, port, API addresses)
#   sudo ./install.sh --name Casa --port 8080 --upstreams 127.0.0.1:9000-9099     no questions (scripts)
# What it makes: /usr/local/bin/pindrel-gateway, /etc/pindrel-gateway/gateway.env (kept on a re-run), the unit
# pindrel-gateway.service and a system user of the same name. Undo it with ./uninstall.sh.
# DESTDIR=<dir> stages everything under <dir> and touches no user, no service (used by the tests).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
dest=${DESTDIR:-}
bin_dir=/usr/local/bin
conf_dir=/etc/pindrel-gateway
unit_dir=/etc/systemd/system
name="" port="" upstreams="" assume_yes=0

while [ $# -gt 0 ]; do
  case $1 in
    --name) name=${2:?--name precisa de um valor}; shift 2 ;;
    --port) port=${2:?--port precisa de um valor}; shift 2 ;;
    --upstreams) upstreams=${2:?--upstreams precisa de um valor}; shift 2 ;;
    -y|--yes) assume_yes=1; shift ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "opção desconhecida: $1 (veja --help)" >&2; exit 2 ;;
  esac
done

if [ -z "$dest" ] && [ "$(id -u)" -ne 0 ]; then
  echo "Rode como root: sudo $0" >&2
  exit 1
fi
for f in gateway pindrel-gateway.service gateway.env.example; do
  [ -f "$here/$f" ] || { echo "falta $f ao lado do instalador (use a pasta descompactada da release)" >&2; exit 1; }
done

valid_port() { case $1 in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
# a name is shown to people on the network: one line, 1-64 characters, no quotes or hash that a settings file would misread
valid_name() { [ -n "$1" ] && [ "${#1}" -le 64 ] && [ "$(printf %s "$1" | tr -d '[:cntrl:]')" = "$1" ] && case $1 in *[\"\'#\\]*) return 1 ;; esac; }
valid_upstreams() { [ -n "$1" ] && case $1 in *[!]0-9a-fA-F.:,[-]*) return 1 ;; esac; }

ask() { # ask <prompt> <default> -> answer (the default on an empty line)
  printf '%s [%s]: ' "$1" "$2" >&2
  IFS= read -r answer || answer=""
  printf %s "${answer:-$2}"
}
interactive=0
if [ -t 0 ] && [ "$assume_yes" = 0 ] && { [ -z "$name" ] || [ -z "$port" ] || [ -z "$upstreams" ]; } && [ ! -f "$dest$conf_dir/gateway.env" ]; then
  interactive=1
fi
if [ ! -f "$dest$conf_dir/gateway.env" ]; then
  if [ "$interactive" = 1 ]; then
    [ -n "$name" ] || name=$(ask "Nome do servidor na rede" "Pindrel")
    [ -n "$port" ] || port=$(ask "Porta do gateway" "8080")
    [ -n "$upstreams" ] || upstreams=$(ask "Endereços da API (ip:porta ou ip:porta-porta, separados por vírgula)" "127.0.0.1:9000-9099")
  fi
  name=${name:-Pindrel}; port=${port:-8080}; upstreams=${upstreams:-127.0.0.1:9000-9099}
  valid_name "$name" || { echo "nome inválido: use de 1 a 64 caracteres, sem aspas, # nem barra invertida" >&2; exit 2; }
  valid_port "$port" || { echo "porta inválida: $port (de 1 a 65535)" >&2; exit 2; }
  valid_upstreams "$upstreams" || { echo "endereços da API inválidos: $upstreams" >&2; exit 2; }
fi

install -d -m 0755 "$dest$bin_dir" "$dest$unit_dir"
install -d -m 0750 "$dest$conf_dir"
if [ -z "$dest" ]; then
  id -u pindrel-gateway >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin pindrel-gateway
  command -v systemctl >/dev/null 2>&1 && systemctl stop pindrel-gateway 2>/dev/null || true
fi
install -m 0755 "$here/gateway" "$dest$bin_dir/pindrel-gateway"

conf="$dest$conf_dir/gateway.env"
if [ -f "$conf" ]; then
  echo "Mantive a configuração que já existe: $conf_dir/gateway.env"
else
  {
    echo "# Gerado por install.sh. Edite e reinicie: systemctl restart pindrel-gateway"
    echo "SERVER_NAME=$name"
    echo "GATEWAY_PORT=$port"
    echo "UPSTREAMS=$upstreams"
    # the service's own state directory (StateDirectory=pindrel-gateway): who this server is, and the servers it has seen
    echo "SERVER_ID_FILE=/var/lib/pindrel-gateway/server.id"
    echo "KNOWN_SERVERS_FILE=/var/lib/pindrel-gateway/known-servers.pb"
  } >"$conf"
fi
chmod 0640 "$conf"

sed -e "s|@BIN@|$bin_dir/pindrel-gateway|" -e "s|@CONF@|$conf_dir/gateway.env|" "$here/pindrel-gateway.service" >"$dest$unit_dir/pindrel-gateway.service"
chmod 0644 "$dest$unit_dir/pindrel-gateway.service"

if [ -z "$dest" ]; then
  chown root:pindrel-gateway "$dest$conf_dir" "$conf"
  # refuse to enable a service that cannot start
  if ! "$bin_dir/pindrel-gateway" --check --config "$conf"; then
    echo "A configuração tem erro (acima). Corrija $conf e rode: systemctl enable --now pindrel-gateway" >&2
    exit 1
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl enable --now pindrel-gateway
    echo "Gateway instalado e iniciado. Logs (o código de pareamento aparece aqui): journalctl -u pindrel-gateway"
  else
    echo "Instalado, mas não há systemd: inicie com $bin_dir/pindrel-gateway --config $conf_dir/gateway.env"
  fi
else
  echo "Instalado em $dest (modo de teste, sem usuário nem serviço)."
fi
