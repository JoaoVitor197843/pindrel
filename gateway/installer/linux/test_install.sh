#!/bin/sh
# Tests install.sh and uninstall.sh on a staged root (DESTDIR): no user, no service, no root needed.
#   sh gateway/installer/linux/test_install.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# install.sh gives owners and modes (640, 750...) to what it installs, and this test reads them back: that only exists on a
# file system with POSIX permissions and the GNU `stat` (Linux), not on Windows, where this installer has no use (it has its own).
. "$here/../../../.forgejo/scripts/portable-env.sh"
if ! posix_modes "$work"; then
  echo "PULADO - este sistema de arquivos não guarda permissões POSIX (chmod 640 não volta como 640): o install.sh dá dono e modo aos arquivos, e é isso que o teste confere. Rode em Linux."
  exit 0
fi
fails=0 total=0

check() { # check <what> <command...>
  total=$((total + 1)); what=$1; shift
  if "$@" >/dev/null 2>&1; then echo "ok   $what"; else echo "FAIL $what"; fails=$((fails + 1)); fi
}
refuses() { # refuses <what> <command...>: must exit non-zero
  total=$((total + 1)); what=$1; shift
  if "$@" >/dev/null 2>&1; then echo "FAIL $what (it accepted it)"; fails=$((fails + 1)); else echo "ok   $what"; fi
}

# a release folder: a stand-in gateway that understands --check, like the real one
rel="$work/release"; mkdir -p "$rel"
cp "$here/install.sh" "$here/uninstall.sh" "$here/pindrel-gateway.service" "$here/gateway.env.example" "$rel/"
printf '#!/bin/sh\nexit 0\n' >"$rel/gateway"; chmod +x "$rel/gateway"

root="$work/root"
export DESTDIR="$root"
sh "$rel/install.sh" --name "Casa da Vó" --port 8200 --upstreams 127.0.0.1:9000-9003,10.0.0.5:8080 </dev/null >/dev/null 2>&1
conf="$root/etc/pindrel-gateway/gateway.env"
check "installs the program" test -x "$root/usr/local/bin/pindrel-gateway"
check "writes the settings" grep -qx 'SERVER_NAME=Casa da Vó' "$conf"
check "the port and the API addresses are in it" sh -c "grep -qx 'GATEWAY_PORT=8200' '$conf' && grep -qx 'UPSTREAMS=127.0.0.1:9000-9003,10.0.0.5:8080' '$conf'"
check "the identity and the known servers go to the state directory" sh -c "grep -q '^SERVER_ID_FILE=/var/lib/pindrel-gateway/' '$conf' && grep -q '^KNOWN_SERVERS_FILE=/var/lib/pindrel-gateway/' '$conf'"
check "the settings are not world readable" sh -c "[ \"\$(stat -c %a '$conf')\" = 640 ]"
unit="$root/etc/systemd/system/pindrel-gateway.service"
check "the unit points at the installed paths" sh -c "grep -qx 'ExecStart=/usr/local/bin/pindrel-gateway --config /etc/pindrel-gateway/gateway.env' '$unit'"
check "no placeholder is left in the unit" sh -c "! grep -q '@' '$unit'"
check "the unit is hardened" sh -c "grep -q '^NoNewPrivileges=true' '$unit' && grep -q '^ProtectSystem=strict' '$unit'"

# a second run keeps what the person may have edited
echo "EXTRA=edited" >>"$conf"
sh "$rel/install.sh" --name Outro --port 9000 </dev/null >/dev/null 2>&1
check "a re-run keeps the settings file" grep -qx 'EXTRA=edited' "$conf"
check "and does not rewrite them with the new answers" sh -c "! grep -q 'SERVER_NAME=Outro' '$conf'"

# HTTPS: on by default (the phone apps pair over it), in the state directory, and never twice
check "HTTPS is on by default, its CA kept with the state" sh -c "grep -qx 'TLS_AUTO=true' '$conf' && grep -qx 'TLS_DIR=/var/lib/pindrel-gateway/tls' '$conf' && grep -qx 'TLS_PORT=8443' '$conf'"
sh "$rel/install.sh" --https </dev/null >/dev/null 2>&1
check "a re-run with --https does not add it again" sh -c "[ \"\$(grep -c '^TLS_PORT=' '$conf')\" = 1 ]"
h="$work/https"
DESTDIR="$h" sh "$rel/install.sh" --name X --port 8080 --upstreams 127.0.0.1:1 --no-https </dev/null >/dev/null 2>&1
hc="$h/etc/pindrel-gateway/gateway.env"
check "--no-https leaves it off" sh -c "! grep -q '^TLS' '$hc'"
check "a re-run without --https says how to turn it on" sh -c "DESTDIR='$h' sh '$rel/install.sh' </dev/null | grep -q -- '--https'"
check "and changes nothing" sh -c "! grep -q '^TLS' '$hc'"
printf 'GATEWAY_PORT=8443' >>"$hc"   # an edit that left no newline at the end, on the HTTPS port
refuses "a re-run with --https refuses the port the gateway already uses" env DESTDIR="$h" sh "$rel/install.sh" --https
check "and wrote nothing" sh -c "! grep -q '^TLS' '$hc'"
DESTDIR="$h" sh "$rel/install.sh" --https --tls-port 9443 </dev/null >/dev/null 2>&1
check "a re-run with --https turns it on in the kept file" sh -c "grep -qx 'TLS_AUTO=true' '$hc' && grep -qx 'TLS_PORT=9443' '$hc'"
check "the last line without a newline stays whole" grep -qx 'GATEWAY_PORT=8443' "$hc"
rm -rf "$h"
DESTDIR="$h" sh "$rel/install.sh" --name X --port 8080 --upstreams 127.0.0.1:1 --no-https </dev/null >/dev/null 2>&1
printf 'TLS_CERT_FILE=/etc/ssl/c.pem\nTLS_KEY_FILE=/etc/ssl/k.pem\n' >>"$hc"
DESTDIR="$h" sh "$rel/install.sh" --https </dev/null >/dev/null 2>&1
check "certificates somebody else manages stay: only the port is added" sh -c "grep -qx 'TLS_PORT=8443' '$hc' && ! grep -q '^TLS_AUTO' '$hc'"
rm -rf "$h"
refuses "refuses an HTTPS port equal to the gateway's" env DESTDIR="$h" sh "$rel/install.sh" --name X --port 8443 --upstreams 127.0.0.1:1
refuses "refuses a bad HTTPS port" env DESTDIR="$h" sh "$rel/install.sh" --name X --port 8080 --upstreams 127.0.0.1:1 --tls-port 0
check "nothing was written for a bad HTTPS port" test ! -e "$hc"
check "with --no-https the HTTPS port does not matter" env DESTDIR="$h" sh "$rel/install.sh" --name X --port 8443 --upstreams 127.0.0.1:1 --no-https
rm -rf "$h"

# uninstall: the program goes, the settings stay
sh "$rel/uninstall.sh" >/dev/null 2>&1
check "uninstall removes the program and the unit" sh -c "[ ! -e '$root/usr/local/bin/pindrel-gateway' ] && [ ! -e '$unit' ]"
check "uninstall keeps the settings" test -f "$conf"
mkdir -p "$root/var/lib/pindrel-gateway"; : >"$root/var/lib/pindrel-gateway/server.id"
sh "$rel/uninstall.sh" --purge >/dev/null 2>&1
check "--purge removes the settings and the state" sh -c "[ ! -e '$root/etc/pindrel-gateway' ] && [ ! -e '$root/var/lib/pindrel-gateway' ]"
check "uninstalling twice is fine" sh "$rel/uninstall.sh" --purge

# bad answers are refused before anything is written
bad="$work/bad"
for args in "--port 0" "--port 70000" "--port abc" "--name \"\"" "--upstreams has;semicolon" "--upstreams ''" ; do
  rm -rf "$bad"
  refuses "refuses: $args" sh -c "DESTDIR='$bad' sh '$rel/install.sh' $args </dev/null"
  check "nothing was written for: $args" sh -c "[ ! -e '$bad/etc/pindrel-gateway/gateway.env' ]"
done
rm -rf "$bad"
rm -rf "$bad"
refuses "refuses a port that carries a command" env DESTDIR="$bad" sh "$rel/install.sh" --name X --port '80;touch /tmp/pwned' --upstreams 127.0.0.1:1
check "and nothing ran" test ! -e /tmp/pwned
rm -rf "$bad"
check "a name that looks like a command is only text" env DESTDIR="$bad" sh "$rel/install.sh" --name '$(touch /tmp/pwned)' --port 8080 --upstreams 127.0.0.1:1
check "and nothing ran either" test ! -e /tmp/pwned
check "it was written as it came" grep -qxF 'SERVER_NAME=$(touch /tmp/pwned)' "$bad/etc/pindrel-gateway/gateway.env"
rm -rf "$bad"
refuses "refuses a name with quotes" env DESTDIR="$bad" sh "$rel/install.sh" --name 'a"b' --port 8080 --upstreams 127.0.0.1:1
rm -rf "$bad"
refuses "refuses a name with a hash" env DESTDIR="$bad" sh "$rel/install.sh" --name 'a#b' --port 8080 --upstreams 127.0.0.1:1
rm -rf "$bad"
refuses "refuses a name over 64 characters" env DESTDIR="$bad" sh "$rel/install.sh" --name "$(printf 'x%.0s' $(seq 1 65))" --port 8080 --upstreams 127.0.0.1:1
rm -rf "$bad"
refuses "refuses an unknown option" env DESTDIR="$bad" sh "$rel/install.sh" --nope
refuses "uninstall refuses an unknown option" env DESTDIR="$bad" sh "$rel/uninstall.sh" --nope
check "an IPv6 address is accepted" env DESTDIR="$bad" sh "$rel/install.sh" --name X --port 8080 --upstreams '[::1]:9000' </dev/null

# without the program next to it, it says so instead of installing half
rm -rf "$bad"; mv "$rel/gateway" "$rel/gateway.gone"
rm -rf "$bad"
refuses "refuses a release folder without the program" env DESTDIR="$bad" sh "$rel/install.sh" --name X --port 8080 --upstreams 127.0.0.1:1

echo
if [ "$fails" -eq 0 ]; then echo "todos os $total testes passaram"; else echo "$fails de $total falharam"; exit 1; fi
