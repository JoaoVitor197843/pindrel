#!/bin/sh
# Atualiza o Plany a partir do registry: baixa as imagens novas, recria os contêineres e espera ficarem
# saudáveis; se não ficarem, volta para as imagens anteriores e não tenta a mesma versão de novo.
# Pensado para rodar por um timer do systemd (deploy/install-timer.sh). Idempotente: sem imagem nova não faz nada.
#
# Variáveis (todas opcionais):
#   REGISTRY, REGISTRY_OWNER, PLANY_TAG  de onde vêm as imagens (mesmos nomes do compose.registry.yml)
#   PLANY_REPLICAS   réplicas da API (2)
#   WAIT_TIMEOUT     segundos esperando ficarem saudáveis (120)
#   PLANY_STATE_DIR  onde guardar a versão que falhou (./.deploy-state)
#   UPDATE_GIT       1 = antes, `git pull --ff-only` para trazer mudanças do compose (1)
#
# O corpo fica numa função e o arquivo termina em `exit`: o git pull pode trocar este arquivo enquanto
# ele roda, e o sh lê o script aos poucos.

main() {
  cd "$(dirname "$0")/.."
  : "${REGISTRY:=raspberry-joao.tail7a986c.ts.net}" "${REGISTRY_OWNER:=joao_vitor}" "${PLANY_TAG:=latest}"
  : "${PLANY_REPLICAS:=2}" "${WAIT_TIMEOUT:=120}" "${PLANY_STATE_DIR:=./.deploy-state}" "${UPDATE_GIT:=1}"
  export REGISTRY REGISTRY_OWNER PLANY_TAG

  say() { echo "plany-update: $*"; }
  compose() { docker compose -f compose.yml -f compose.lb.yml -f compose.registry.yml "$@"; }
  ref_of() { echo "$REGISTRY/$REGISTRY_OWNER/$1:$PLANY_TAG"; }
  # id da imagem do contêiner que roda o serviço $1 (vazio se não há)
  running_image() {
    cid=$(compose ps -q "$1" | head -n 1)
    [ -n "$cid" ] && docker inspect -f '{{.Image}}' "$cid" || true
  }

  mkdir -p "$PLANY_STATE_DIR"
  # uma atualização por vez (o timer pode disparar de novo enquanto uma demora)
  exec 9>"$PLANY_STATE_DIR/lock"
  flock -n 9 || { say "outra atualização está em andamento"; return 0; }

  if [ "$UPDATE_GIT" = 1 ] && [ -d .git ]; then
    git pull --ff-only --quiet || say "aviso: git pull falhou, seguindo com o compose atual"
  fi

  services="plany gateway"
  old_plany=$(running_image plany)
  old_gateway=$(running_image gateway)

  compose pull --quiet $services || { say "não foi possível baixar as imagens (rede ou login no registry)"; return 1; }

  new_plany=$(docker image inspect -f '{{.Id}}' "$(ref_of plany)")
  new_gateway=$(docker image inspect -f '{{.Id}}' "$(ref_of plany-gateway)")

  # a versão é o PAR de imagens: uma imagem igual à da falha, com a outra já diferente, é outra versão
  if [ "$new_plany $new_gateway" = "$(cat "$PLANY_STATE_DIR/failed" 2>/dev/null)" ]; then
    say "a versão publicada já falhou aqui e foi revertida; esperando uma nova"
    return 0
  fi
  if [ "$new_plany" = "$old_plany" ] && [ "$new_gateway" = "$old_gateway" ]; then
    say "já está na versão mais recente"
    return 0
  fi

  say "atualizando (api ${old_plany:-nova} -> $new_plany)"
  if compose up -d --wait --wait-timeout "$WAIT_TIMEOUT" --scale plany="$PLANY_REPLICAS" $services; then
    rm -f "$PLANY_STATE_DIR/failed"
    docker image prune -f >/dev/null 2>&1 || true
    say "atualizado"
    return 0
  fi

  say "a versão nova não ficou saudável em ${WAIT_TIMEOUT}s"
  echo "$new_plany $new_gateway" >"$PLANY_STATE_DIR/failed"
  if [ -z "$old_plany" ] || [ -z "$old_gateway" ]; then
    say "não havia versão anterior para voltar"
    return 1
  fi
  # a tag do registry passa a apontar para a imagem de antes e o compose recria com ela
  docker tag "$old_plany" "$(ref_of plany)"
  docker tag "$old_gateway" "$(ref_of plany-gateway)"
  if compose up -d --wait --wait-timeout "$WAIT_TIMEOUT" --scale plany="$PLANY_REPLICAS" $services; then
    say "revertido para a versão anterior"
  else
    say "ATENÇÃO: nem a versão anterior ficou saudável"
  fi
  return 1
}

main "$@"
exit $?
