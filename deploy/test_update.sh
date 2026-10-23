#!/bin/sh
# Testa deploy/update.sh com um `docker` falso (sem Docker, sem rede, sem registry):
#   sh deploy/test_update.sh
# O falso guarda o estado em arquivos e reproduz o que o script usa: ps, inspect, pull, tag, up --wait.
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/state"

cat >"$work/bin/docker" <<'STUB'
#!/bin/sh
S=$STUB_DIR
echo "$*" >>"$S/calls"
case "$1" in
  compose)
    shift
    while [ "${1:-}" = -f ]; do shift 2; done
    case "$1" in
      ps) svc=$3; [ -s "$S/running_$svc" ] && echo "cid-$svc"; exit 0 ;;
      pull)
        [ -e "$S/pull_fail" ] && exit 1
        cp "$S/registry_plany" "$S/local_plany"; cp "$S/registry_gateway" "$S/local_gateway"; exit 0 ;;
      up)
        echo up >>"$S/ups"
        if grep -qx -e "$(cat "$S/local_plany")" -e "$(cat "$S/local_gateway")" "$S/bad" 2>/dev/null; then exit 1; fi
        cp "$S/local_plany" "$S/running_plany"; cp "$S/local_gateway" "$S/running_gateway"; exit 0 ;;
    esac ;;
  inspect) svc=${4#cid-}; cat "$S/running_$svc"; exit 0 ;;
  image)
    case "$2" in
      inspect) case "$5" in *plany-gateway*) cat "$S/local_gateway" ;; *) cat "$S/local_plany" ;; esac; exit 0 ;;
      prune) exit 0 ;;
    esac ;;
  tag)
    case "$3" in *plany-gateway*) echo "$2" >"$S/local_gateway" ;; *) echo "$2" >"$S/local_plany" ;; esac
    echo tag >>"$S/tags"; exit 0 ;;
esac
echo "docker falso: comando inesperado: $*" >&2
exit 99
STUB
chmod +x "$work/bin/docker"

# a árvore do projeto fica fora do repositório real: o script faz `cd ..` a partir de onde está
mkdir -p "$work/proj/deploy"
cp "$here/update.sh" "$work/proj/deploy/update.sh"
for f in compose.yml compose.lb.yml compose.registry.yml; do : >"$work/proj/$f"; done

fails=0
t=0
check() { # check "descrição" comando...
  desc=$1; shift
  t=$((t + 1))
  if "$@"; then echo "ok $t - $desc"; else echo "FALHOU $t - $desc"; fails=$((fails + 1)); fi
}
S=$work/stub
reset() { # reset <rodando-api> <rodando-gw> <registry-api> <registry-gw>
  rm -rf "$S" "$work/state"; mkdir -p "$S" "$work/state"
  printf '%s' "$1" >"$S/running_plany"; printf '%s' "$2" >"$S/running_gateway"
  printf '%s' "$1" >"$S/local_plany"; printf '%s' "$2" >"$S/local_gateway"
  echo "$3" >"$S/registry_plany"; echo "$4" >"$S/registry_gateway"
  : >"$S/calls"; : >"$S/ups"; : >"$S/tags"
}
run() {
  STUB_DIR=$S PATH="$work/bin:$PATH" UPDATE_GIT=0 PLANY_STATE_DIR="$work/state" PLANY_REPLICAS=2 \
    sh "$work/proj/deploy/update.sh" >"$work/out" 2>&1
  rc=$?
}
ups() { wc -l <"$S/ups" | tr -d ' '; }
running() { cat "$S/running_plany"; }
said() { grep -q "$1" "$work/out"; }

# 1. nada novo: não recria nada
reset sha-A sha-A sha-A sha-A; run
check "sem versão nova não recria" test "$rc" = 0 -a "$(ups)" = 0
check "avisa que está atualizado" said "mais recente"

# 2. versão nova saudável
reset sha-A sha-A sha-B sha-B; run
check "versão nova saudável: sobe uma vez e termina bem" test "$rc" = 0 -a "$(ups)" = 1
check "passa a rodar a versão nova" test "$(running)" = sha-B

# 3. versão nova doente: volta para a anterior
reset sha-A sha-A sha-B sha-B; echo sha-B >"$S/bad"; run
check "versão doente: falha o script" test "$rc" = 1
check "versão doente: sobe a nova e depois a anterior" test "$(ups)" = 2
check "versão doente: volta a rodar a anterior" test "$(running)" = sha-A
check "versão doente: marca a que falhou" test "$(cat "$work/state/failed")" = "sha-B sha-B"

# 4. a mesma versão doente não é tentada de novo
: >"$S/ups"; run
check "a versão que falhou não é tentada outra vez" test "$rc" = 0 -a "$(ups)" = 0
check "avisa que espera uma nova" said "esperando uma nova"

# 5. uma versão corrigida depois da falha entra
echo sha-C >"$S/registry_plany"; echo sha-C >"$S/registry_gateway"; run
check "versão nova depois da falha é aplicada" test "$rc" = 0 -a "$(running)" = sha-C
check "sucesso limpa a marca de falha" test ! -e "$work/state/failed"

# 5b. só o gateway repetido da falha não basta para pular: o par é que conta
reset sha-A sha-A sha-B sha-B; echo sha-B >"$S/bad"; run
# (a API estava quebrada, não o gateway: a imagem sha-B do gateway em si presta)
: >"$S/bad"; echo sha-D >"$S/registry_plany"; run
check "mesma imagem do gateway, API nova: é outra versão" test "$rc" = 0 -a "$(running)" = sha-D

# 6. só o gateway doente também reverte os dois
reset sha-A sha-A sha-A sha-G2; echo sha-G2 >"$S/bad"; run
check "gateway doente: reverte" test "$rc" = 1 -a "$(running)" = sha-A

# 7. sem rede / sem login: nada muda
reset sha-A sha-A sha-B sha-B; : >"$S/pull_fail"; run
check "falha ao baixar: erro e nada recriado" test "$rc" = 1 -a "$(ups)" = 0 -a "$(running)" = sha-A

# 8. primeira instalação
reset "" "" sha-B sha-B; run
check "primeira instalação saudável sobe" test "$rc" = 0 -a "$(running)" = sha-B
reset "" "" sha-B sha-B; echo sha-B >"$S/bad"; run
check "primeira instalação doente: falha sem tentar reverter" test "$rc" = 1 -a "$(ups)" = 1 -a ! -s "$S/tags"
check "primeira instalação doente: avisa" said "não havia versão anterior"

# 9. duas atualizações ao mesmo tempo: a segunda desiste sem mexer em nada
reset sha-A sha-A sha-B sha-B
( exec 9>"$work/state/lock"; flock 9; sleep 3 ) &
holder=$!
sleep 0.5; run
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
check "atualização concorrente é ignorada" test "$rc" = 0 -a "$(ups)" = 0 -a ! -s "$S/calls"

# 10. o script resiste a ser trocado enquanto roda (o corpo está numa função)
check "o arquivo termina em exit (sh lê aos poucos)" test "$(tail -n 2 "$here/update.sh" | tr '\n' ' ')" = 'main "$@" exit $? '

# 11. as units do systemd saem corretas e apontam para este diretório
out=$(sh "$here/install-timer.sh" --print)
proj=$(cd "$here/.." && pwd)
check "service roda o update.sh deste diretório" sh -c 'echo "$1" | grep -q "^ExecStart=$2/deploy/update.sh$"' _ "$out" "$proj"
check "service é oneshot com timeout" sh -c 'echo "$1" | grep -q "^Type=oneshot" && echo "$1" | grep -q "^TimeoutStartSec="' _ "$out"
check "timer repete a cada 5 min e sobrevive a reinício" sh -c 'echo "$1" | grep -q "^OnUnitActiveSec=5min" && echo "$1" | grep -q "^Persistent=true"' _ "$out"
if command -v systemd-analyze >/dev/null 2>&1; then
  mkdir -p "$work/units"
  sh "$here/install-timer.sh" --print | awk -v d="$work/units" '/^# plany-update/{f=d"/"$2; next} f{print > f}'
  check "systemd-analyze aprova as units" systemd-analyze verify "$work/units/plany-update.timer" "$work/units/plany-update.service"
fi

echo
if [ "$fails" = 0 ]; then echo "todos os $t testes passaram"; else echo "$fails de $t falharam"; exit 1; fi
