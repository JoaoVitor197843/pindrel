#!/bin/sh
# A small local CA and a server certificate for this machine (what mkcert does), to test HTTPS the way a real client
# validates it: chain, host name / IP and dates. Output in $1 (default ./tls-local). Nothing here is committed.
set -e
out=${1:-./tls-local}
lan=${LAN_IP:-$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1)}
mkdir -p "$out" && cd "$out"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 -keyout ca.key -out ca.pem \
  -subj "/CN=Pindrel test CA" -addext "basicConstraints=critical,CA:TRUE,pathlen:0" -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
issue() { # name days extra-san
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$1.key" -out "$1.csr" -subj "/CN=pindrel" 2>/dev/null
  printf "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1%s\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth\n" "$3" > "$1.ext"
  openssl x509 -req -in "$1.csr" -CA ca.pem -CAkey ca.key -CAcreateserial -days "$2" -extfile "$1.ext" -out "$1.pem" 2>/dev/null
}
issue server 30 ",IP:${lan:-127.0.0.1}"
issue expired 1 ""
# a certificate whose dates are already over (openssl >= 3.4 has -not_before/-not_after for x509 -req)
openssl x509 -req -in expired.csr -CA ca.pem -CAkey ca.key -CAcreateserial -not_before 20200101000000Z -not_after 20200102000000Z -extfile expired.ext -out expired.pem 2>/dev/null || true
echo "CA: $out/ca.pem  server: $out/server.pem  (LAN IP in the SAN: ${lan:-none})"
