#!/bin/sh
# Tests deploy/update.sh with a fake `docker` (no Docker, no network, no registry):
#   sh deploy/test_update.sh
# The fake `docker` (deploy/fake_docker.py) simulates containers, images and compose's --wait.
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/state"

cp "$here/fake_docker.py" "$work/bin/docker"
chmod +x "$work/bin/docker"

# the project tree stays outside the real repository: the script does `cd ..` from where it is
mkdir -p "$work/proj/deploy"
cp "$here/update.sh" "$work/proj/deploy/update.sh"
for f in compose.yml compose.lb.yml compose.registry.yml; do : >"$work/proj/$f"; done

fails=0
t=0
check() { # check "description" command...
  desc=$1; shift
  t=$((t + 1))
  if "$@"; then echo "ok $t - $desc"; else echo "FALHOU $t - $desc"; fails=$((fails + 1)); fi
}
S=$work/stub

# fake world: reset <api-running> <gw-running> <api-in-registry> <gw-in-registry> [replicas]
# ("" in the running ones = no container yet)
reset() {
  rm -rf "$S" "$work/state"; mkdir -p "$S" "$work/state"; rm -f "$work/proj/.env"
  python3 - "$S" "$1" "$2" "$3" "$4" "${5:-2}" <<'PY'
import json, sys
s, api, gw, rapi, rgw, n = sys.argv[1:7]
cs, seq = [], 0
if api:
    for _ in range(int(n)):
        seq += 1
        cs.append({"id": "c%d" % seq, "svc": "plany", "image": api, "health": "healthy"})
    seq += 1
    cs.append({"id": "c%d" % seq, "svc": "gateway", "image": gw, "health": "healthy"})
json.dump({"local": {"plany": api or rapi, "gateway": gw or rgw}, "registry": {"plany": rapi, "gateway": rgw},
           "containers": cs, "seq": seq, "bad": []}, open(s + "/world.json", "w"))
PY
  : >"$S/calls"; : >"$S/ups"; : >"$S/tags"; : >"$S/env"; : >"$S/serving"
}
# w <python expression on `w`>: reads or changes the fake world
w() {
  python3 - "$S/world.json" "$1" <<'PY'
import json, sys
f, expr = sys.argv[1:3]
w = json.load(open(f))
try:
    code = compile(expr, "<w>", "eval")
    r = eval(code)
except SyntaxError:
    exec(expr)
    r = None
json.dump(w, open(f, "w"))
if r is not None: print(r)
PY
}
bad() { w "w['bad'].append('$1')"; }
run() {
  STUB_DIR=$S PATH="$work/bin:$PATH" UPDATE_GIT=0 PLANY_STATE_DIR="$work/state" PLANY_REPLICAS="${REPLICAS-}" COMPOSE_FILE="${CF-}" \
    sh "$work/proj/deploy/update.sh" >"$work/out" 2>&1
  rc=$?
}
api_images() { w "' '.join(sorted(c['image'] for c in w['containers'] if c['svc']=='plany'))"; }
api_ids() { w "' '.join(sorted(c['id'] for c in w['containers'] if c['svc']=='plany'))"; }
gw_image() { w "[c['image'] for c in w['containers'] if c['svc']=='gateway'][0]"; }
unhealthy() { w "len([c for c in w['containers'] if c['health']!='healthy'])"; }
ups() { wc -l <"$S/ups" | tr -d ' '; }
said() { grep -q "$1" "$work/out"; }
# smallest number of healthy replicas left at any moment when an old one was stopped
min_serving() { sort -n "$S/serving" | head -n 1; }

fails=0
t=0
check() { # check "description" command...
  desc=$1; shift
  t=$((t + 1))
  if "$@"; then echo "ok $t - $desc"; else echo "FALHOU $t - $desc"; fails=$((fails + 1)); fi
}

# 1. nothing new: touches nothing
reset A A A A; run
check "sem versão nova não recria" test "$rc" = 0 -a "$(ups)" = 0
check "avisa que está atualizado" said "mais recente"

# 2. healthy new version: rolling, always with a replica serving
reset A A B B; run
check "versão nova saudável termina bem" test "$rc" = 0
check "todas as réplicas e o gateway passam à versão nova" test "$(api_images)" = "B B" -a "$(gw_image)" = B
check "continua com 2 réplicas" test "$(w "len([c for c in w['containers'] if c['svc']=='plany'])")" = 2
check "rolling: nunca ficou sem réplica saudável" test "$(min_serving)" -ge 1
check "rolling: as réplicas antigas foram trocadas uma por vez" test "$(grep -c 'no-recreate' "$S/calls")" = 2
check "o log traz o tempo de cada etapa e o total" sh -c 'grep -q "pull das imagens: [0-9]*s" "$1" && grep -q "réplica nova saudável: [0-9]*s" "$1" && grep -q "atualizado em [0-9]*s" "$1"' _ "$work/out"

# 3. sick new version: the old replicas are not even touched
reset A A B B; ids=$(api_ids); bad B; run
check "versão doente: o script falha" test "$rc" = 1
check "versão doente: as réplicas antigas continuam as mesmas" test "$(api_ids)" = "$ids" -a "$(api_images)" = "A A"
check "versão doente: nenhum contêiner doente sobra" test "$(unhealthy)" = 0
check "versão doente: as antigas seguiram servindo (2 saudáveis o tempo todo)" test "$(min_serving)" -ge 2
check "versão doente: marca o par que falhou" test "$(cat "$work/state/failed")" = "B B"

# 4. the same sick version is not tried again
: >"$S/ups"; run
check "a versão que falhou não é tentada outra vez" test "$rc" = 0 -a "$(ups)" = 0
check "avisa que espera uma nova" said "esperando uma nova"

# 5. a fixed version after the failure goes in
w "w['registry'].update({'plany':'C','gateway':'C'})"; run
check "versão nova depois da falha é aplicada" test "$rc" = 0 -a "$(api_images)" = "C C"
check "sucesso limpa a marca de falha" test ! -e "$work/state/failed"

# 5b. only the whole pair counts as "the one that failed"
reset A A B B; bad B; run
w "w['bad'].clear(); w['registry'].update({'plany':'D'})"; run
check "mesma imagem do gateway, API nova: é outra versão" test "$rc" = 0 -a "$(api_images)" = "D D"

# 6. failure in the middle of the switch (the 2nd new replica does not come up): everything goes back to the previous version, without cutting the service
reset A A B B; w "w.update(bad_from_creation=2)"; run
check "falha no meio: o script falha" test "$rc" = 1
check "falha no meio: volta às imagens antigas" test "$(api_images)" = "A A" -a "$(gw_image)" = A
check "falha no meio: nenhum contêiner doente sobra" test "$(unhealthy)" = 0
check "falha no meio: nunca ficou sem réplica saudável" test "$(min_serving)" -ge 1

# 7. only the gateway sick: reverts the API too
reset A A A G; bad G; run
check "gateway doente: o script falha e reverte" test "$rc" = 1 -a "$(gw_image)" = A -a "$(api_images)" = "A A"
check "gateway doente: não deixa contêiner doente" test "$(unhealthy)" = 0

# 8. no network / no login: nothing changes
reset A A B B; w "w.update(pull_fail=True)"; ids=$(api_ids); run
check "falha ao baixar: erro e nada recriado" test "$rc" = 1 -a "$(ups)" = 0 -a "$(api_ids)" = "$ids"

# 9. first install
reset "" "" B B; run
check "primeira instalação saudável sobe tudo" test "$rc" = 0 -a "$(api_images)" = "B B" -a "$(gw_image)" = B
reset "" "" B B; bad B; run
check "primeira instalação doente: falha sem tentar reverter" test "$rc" = 1 -a ! -s "$S/tags"
check "primeira instalação doente: avisa" said "não havia versão anterior"

# 10. with a single replica, the rolling update also works (brings the new one up next to it before taking the old one down)
reset A A B B 1; run
check "uma réplica: troca sem ficar sem servir" test "$rc" = 0 -a "$(api_images)" = "B" -a "$(min_serving)" -ge 1

# 11. three replicas: one at a time
reset A A B B 3; run
check "três réplicas: todas na versão nova, sempre com 2+ servindo" test "$(api_images)" = "B B B" -a "$(min_serving)" -ge 2

# 12. two updates at the same time: the second gives up without touching anything
reset A A B B
( exec 9>"$work/state/lock"; flock 9; sleep 3 ) &
holder=$!
sleep 0.5; run
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
check "atualização concorrente é ignorada" test "$rc" = 0 -a "$(ups)" = 0 -a ! -s "$S/calls"

# 13. compose files: default, or the environment's COMPOSE_FILE, or the .env's (server with its own tweaks)
reset A A B B; run
check "sem COMPOSE_FILE usa os três arquivos padrão" grep -q "COMPOSE_FILE=compose.yml:compose.lb.yml:compose.registry.yml" "$S/env"
reset A A B B; echo "COMPOSE_FILE=a.yml:b.yml" >"$work/proj/.env"; run
check "COMPOSE_FILE do .env não é sobrescrito" test "$rc" = 0 -a -z "$(grep -v 'COMPOSE_FILE=$' "$S/env" | sort -u | grep -v '^$' || true)"
reset A A B B; CF=x.yml:y.yml run
check "COMPOSE_FILE do ambiente é respeitado" grep -q "COMPOSE_FILE=x.yml:y.yml" "$S/env"

# 14. PLANY_REPLICAS sets the final number of replicas
reset A A A A; w "w['registry'].update({'plany':'B'})"; REPLICAS=3 run
check "PLANY_REPLICAS=3 termina com 3 réplicas na versão nova" test "$(api_images)" = "B B B"

# 15. the script survives being swapped while it runs (the body is in a function)
check "o arquivo termina em exit (sh lê aos poucos)" test "$(tail -n 2 "$here/update.sh" | tr '\n' ' ')" = 'main "$@" exit $? '

# 16. the systemd units come out right and point to this directory
out=$(sh "$here/install-timer.sh" --print)
proj=$(cd "$here/.." && pwd)
check "service roda o update.sh deste diretório" sh -c 'echo "$1" | grep -q "^ExecStart=$2/deploy/update.sh$"' _ "$out" "$proj"
check "service é oneshot com timeout" sh -c 'echo "$1" | grep -q "^Type=oneshot" && echo "$1" | grep -q "^TimeoutStartSec="' _ "$out"
check "service é restrito: sem privilégios novos, sistema só de leitura e só o diretório do projeto gravável" sh -c 'echo "$1" | grep -q "^NoNewPrivileges=yes" && echo "$1" | grep -q "^ProtectSystem=strict" && echo "$1" | grep -q "^ReadWritePaths=$2 "' _ "$out" "$proj"
check "timer repete a cada 1 min e sobrevive a reinício" sh -c 'echo "$1" | grep -q "^OnUnitActiveSec=1min" && echo "$1" | grep -q "^Persistent=true"' _ "$out"
if command -v systemd-analyze >/dev/null 2>&1; then
  mkdir -p "$work/units"
  sh "$here/install-timer.sh" --print | awk -v d="$work/units" '/^# plany-update/{f=d"/"$2; next} f{print > f}'
  check "systemd-analyze aprova as units" systemd-analyze verify "$work/units/plany-update.timer" "$work/units/plany-update.service"
fi

echo
if [ "$fails" = 0 ]; then echo "todos os $t testes passaram"; else echo "$fails de $t falharam"; exit 1; fi
