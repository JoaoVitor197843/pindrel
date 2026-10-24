#!/bin/sh
# Testa deploy/update.sh com um `docker` falso (sem Docker, sem rede, sem registry):
#   sh deploy/test_update.sh
# O `docker` falso (deploy/fake_docker.py) simula contêineres, imagens e o --wait do compose.
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/state"

cp "$here/fake_docker.py" "$work/bin/docker"
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

# mundo falso: reset <api-rodando> <gw-rodando> <api-no-registry> <gw-no-registry> [réplicas]
# ("" nas rodando = ainda não há contêiner nenhum)
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
# w <expressão python sobre `w`>: lê ou altera o mundo falso
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
# menor número de réplicas saudáveis que restou em qualquer momento em que uma antiga foi parada
min_serving() { sort -n "$S/serving" | head -n 1; }

fails=0
t=0
check() { # check "descrição" comando...
  desc=$1; shift
  t=$((t + 1))
  if "$@"; then echo "ok $t - $desc"; else echo "FALHOU $t - $desc"; fails=$((fails + 1)); fi
}

# 1. nada novo: não mexe em nada
reset A A A A; run
check "sem versão nova não recria" test "$rc" = 0 -a "$(ups)" = 0
check "avisa que está atualizado" said "mais recente"

# 2. versão nova saudável: rolling, sempre com réplica servindo
reset A A B B; run
check "versão nova saudável termina bem" test "$rc" = 0
check "todas as réplicas e o gateway passam à versão nova" test "$(api_images)" = "B B" -a "$(gw_image)" = B
check "continua com 2 réplicas" test "$(w "len([c for c in w['containers'] if c['svc']=='plany'])")" = 2
check "rolling: nunca ficou sem réplica saudável" test "$(min_serving)" -ge 1
check "rolling: as réplicas antigas foram trocadas uma por vez" test "$(grep -c 'no-recreate' "$S/calls")" = 2

# 3. versão nova doente: as réplicas antigas nem chegam a ser tocadas
reset A A B B; ids=$(api_ids); bad B; run
check "versão doente: o script falha" test "$rc" = 1
check "versão doente: as réplicas antigas continuam as mesmas" test "$(api_ids)" = "$ids" -a "$(api_images)" = "A A"
check "versão doente: nenhum contêiner doente sobra" test "$(unhealthy)" = 0
check "versão doente: as antigas seguiram servindo (2 saudáveis o tempo todo)" test "$(min_serving)" -ge 2
check "versão doente: marca o par que falhou" test "$(cat "$work/state/failed")" = "B B"

# 4. a mesma versão doente não é tentada de novo
: >"$S/ups"; run
check "a versão que falhou não é tentada outra vez" test "$rc" = 0 -a "$(ups)" = 0
check "avisa que espera uma nova" said "esperando uma nova"

# 5. uma versão corrigida depois da falha entra
w "w['registry'].update({'plany':'C','gateway':'C'})"; run
check "versão nova depois da falha é aplicada" test "$rc" = 0 -a "$(api_images)" = "C C"
check "sucesso limpa a marca de falha" test ! -e "$work/state/failed"

# 5b. só o par inteiro conta como "a que falhou"
reset A A B B; bad B; run
w "w['bad'].clear(); w['registry'].update({'plany':'D'})"; run
check "mesma imagem do gateway, API nova: é outra versão" test "$rc" = 0 -a "$(api_images)" = "D D"

# 6. falha no meio da troca (a 2ª réplica nova não sobe): volta tudo à versão anterior, sem cortar o serviço
reset A A B B; w "w.update(bad_from_creation=2)"; run
check "falha no meio: o script falha" test "$rc" = 1
check "falha no meio: volta às imagens antigas" test "$(api_images)" = "A A" -a "$(gw_image)" = A
check "falha no meio: nenhum contêiner doente sobra" test "$(unhealthy)" = 0
check "falha no meio: nunca ficou sem réplica saudável" test "$(min_serving)" -ge 1

# 7. só o gateway doente: reverte também a API
reset A A A G; bad G; run
check "gateway doente: o script falha e reverte" test "$rc" = 1 -a "$(gw_image)" = A -a "$(api_images)" = "A A"
check "gateway doente: não deixa contêiner doente" test "$(unhealthy)" = 0

# 8. sem rede / sem login: nada muda
reset A A B B; w "w.update(pull_fail=True)"; ids=$(api_ids); run
check "falha ao baixar: erro e nada recriado" test "$rc" = 1 -a "$(ups)" = 0 -a "$(api_ids)" = "$ids"

# 9. primeira instalação
reset "" "" B B; run
check "primeira instalação saudável sobe tudo" test "$rc" = 0 -a "$(api_images)" = "B B" -a "$(gw_image)" = B
reset "" "" B B; bad B; run
check "primeira instalação doente: falha sem tentar reverter" test "$rc" = 1 -a ! -s "$S/tags"
check "primeira instalação doente: avisa" said "não havia versão anterior"

# 10. com uma réplica só, o rolling também funciona (sobe a nova ao lado antes de tirar a antiga)
reset A A B B 1; run
check "uma réplica: troca sem ficar sem servir" test "$rc" = 0 -a "$(api_images)" = "B" -a "$(min_serving)" -ge 1

# 11. três réplicas: uma por vez
reset A A B B 3; run
check "três réplicas: todas na versão nova, sempre com 2+ servindo" test "$(api_images)" = "B B B" -a "$(min_serving)" -ge 2

# 12. duas atualizações ao mesmo tempo: a segunda desiste sem mexer em nada
reset A A B B
( exec 9>"$work/state/lock"; flock 9; sleep 3 ) &
holder=$!
sleep 0.5; run
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
check "atualização concorrente é ignorada" test "$rc" = 0 -a "$(ups)" = 0 -a ! -s "$S/calls"

# 13. arquivos do compose: padrão, ou o COMPOSE_FILE do ambiente, ou o do .env (servidor com ajustes próprios)
reset A A B B; run
check "sem COMPOSE_FILE usa os três arquivos padrão" grep -q "COMPOSE_FILE=compose.yml:compose.lb.yml:compose.registry.yml" "$S/env"
reset A A B B; echo "COMPOSE_FILE=a.yml:b.yml" >"$work/proj/.env"; run
check "COMPOSE_FILE do .env não é sobrescrito" test "$rc" = 0 -a -z "$(grep -v 'COMPOSE_FILE=$' "$S/env" | sort -u | grep -v '^$' || true)"
reset A A B B; CF=x.yml:y.yml run
check "COMPOSE_FILE do ambiente é respeitado" grep -q "COMPOSE_FILE=x.yml:y.yml" "$S/env"

# 14. PLANY_REPLICAS define o número final de réplicas
reset A A A A; w "w['registry'].update({'plany':'B'})"; REPLICAS=3 run
check "PLANY_REPLICAS=3 termina com 3 réplicas na versão nova" test "$(api_images)" = "B B B"

# 15. o script resiste a ser trocado enquanto roda (o corpo está numa função)
check "o arquivo termina em exit (sh lê aos poucos)" test "$(tail -n 2 "$here/update.sh" | tr '\n' ' ')" = 'main "$@" exit $? '

# 16. as units do systemd saem corretas e apontam para este diretório
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
