#!/bin/sh
# Atualiza o Plany a partir do registry: baixa as imagens novas, recria os contêineres e espera ficarem
# saudáveis; se não ficarem, volta para as imagens anteriores e não tenta a mesma versão de novo.
# Pensado para rodar por um timer do systemd (deploy/install-timer.sh). Idempotente: sem imagem nova não faz nada.
#
# Variáveis (todas opcionais):
#   REGISTRY, REGISTRY_OWNER, PLANY_TAG  de onde vêm as imagens (mesmos nomes do compose.registry.yml)
#   COMPOSE_FILE     arquivos do compose, separados por `:` (se não houver aqui nem no .env: compose.yml,
#                    compose.lb.yml e compose.registry.yml). Um servidor com ajustes próprios (portas, volumes)
#                    põe um compose.<nome>.yml no fim e lista tudo no COMPOSE_FILE do .env.
#   PLANY_REPLICAS   réplicas da API (vazio = o que os arquivos do compose definirem)
#   WAIT_TIMEOUT     segundos esperando ficarem saudáveis (120)
#   PLANY_STATE_DIR  onde guardar a versão que falhou (./.deploy-state)
#   UPDATE_GIT       1 = antes, `git pull --ff-only` para trazer mudanças do compose (1)
#
# O corpo fica numa função e o arquivo termina em `exit`: o git pull pode trocar este arquivo enquanto
# ele roda, e o sh lê o script aos poucos.

main() {
  cd "$(dirname "$0")/.."
  : "${REGISTRY:=raspberry-joao.tail7a986c.ts.net}" "${REGISTRY_OWNER:=joao_vitor}" "${PLANY_TAG:=latest}"
  : "${PLANY_REPLICAS:=}" "${WAIT_TIMEOUT:=120}" "${PLANY_STATE_DIR:=./.deploy-state}" "${UPDATE_GIT:=1}"
  export REGISTRY REGISTRY_OWNER PLANY_TAG

  if [ -z "${COMPOSE_FILE:-}" ] && ! grep -qs '^COMPOSE_FILE=' .env; then
    COMPOSE_FILE=compose.yml:compose.lb.yml:compose.registry.yml
    export COMPOSE_FILE
  fi
  scale=""
  [ -n "$PLANY_REPLICAS" ] && scale="--scale plany=$PLANY_REPLICAS"

  say() { echo "plany-update: $*"; }
  compose() { docker compose "$@"; }
  ref_of() { echo "$REGISTRY/$REGISTRY_OWNER/$1:$PLANY_TAG"; }
  # id da imagem do contêiner que roda o serviço $1 (vazio se não há)
  running_image() {
    cid=$(compose ps -q "$1" | head -n 1)
    [ -n "$cid" ] && docker inspect -f '{{.Image}}' "$cid" || true
  }


  ids_of() { compose ps -q "$1"; }
  image_of() { docker inspect -f '{{.Image}}' "$1"; }
  health_of() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1"; }
  # réplicas da API que NÃO rodam a imagem $1
  stale_of() {
    for c in $(ids_of plany); do
      [ "$(image_of "$c")" = "$1" ] || echo "$c"
    done
  }
  # um `up --wait` falha enquanto sobrar réplica doente: tira as que não estão saudáveis
  purge_unhealthy() {
    for c in $(ids_of plany); do
      case "$(health_of "$c")" in healthy|running) ;; *) docker rm -f "$c" >/dev/null 2>&1 || true ;; esac
    done
  }
  # Rolling update da API: põe a réplica nova (imagem $1) ao lado das antigas, espera ficar saudável e só então
  # derruba uma antiga; repete até nenhuma restar. As antigas seguem servindo o tempo todo (o gateway repete em
  # outra réplica uma conexão que falhou) e, se a nova não subir, nenhuma antiga foi tocada.
  update_to() {
    want=$1
    [ -n "$(stale_of "$want")" ] || return 0
    budget=$(( $(ids_of plany | wc -l) + 1 ))
    while stale=$(stale_of "$want" | head -n 1); [ -n "$stale" ]; do
      budget=$((budget - 1))
      [ "$budget" -ge 0 ] || { say "a troca de réplicas não converge"; purge_unhealthy; return 1; }
      n=$(ids_of plany | wc -l)
      if ! compose up -d --no-deps --no-recreate --wait --wait-timeout "$WAIT_TIMEOUT" --scale plany=$((n + 1)) plany; then
        purge_unhealthy
        return 1
      fi
      docker stop -t 20 "$stale" >/dev/null 2>&1 || true
      docker rm "$stale" >/dev/null 2>&1 || true
    done
    # número de réplicas pedido explicitamente (PLANY_REPLICAS)
    if [ -n "$scale" ]; then compose up -d --no-deps --no-recreate --wait --wait-timeout "$WAIT_TIMEOUT" $scale plany || return 1; fi
    return 0
  }
  # o gateway é um só (rede do host, uma porta): recriá-lo é o único corte, e só se a imagem mudou
  restart_gateway() { compose up -d --no-deps --wait --wait-timeout "$WAIT_TIMEOUT" gateway; }
  finish_ok() {
    rm -f "$PLANY_STATE_DIR/failed"
    docker image prune -f >/dev/null 2>&1 || true
    say "atualizado"
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
  if [ "$new_plany" = "$old_plany" ] && [ "$new_gateway" = "$old_gateway" ] && [ -z "$(stale_of "$new_plany")" ]; then
    say "já está na versão mais recente"
    return 0
  fi

  say "atualizando (api ${old_plany:-nova} -> $new_plany)"
  if [ -z "$old_plany" ]; then
    # primeira instalação: não há réplica servindo que valha proteger
    if compose up -d --wait --wait-timeout "$WAIT_TIMEOUT" $scale $services; then
      finish_ok; return 0
    fi
    echo "$new_plany $new_gateway" >"$PLANY_STATE_DIR/failed"
    say "a versão nova não ficou saudável e não havia versão anterior para voltar"
    return 1
  fi

  if update_to "$new_plany" && restart_gateway; then
    finish_ok; return 0
  fi

  say "a versão nova não ficou saudável (o compose up --wait falhou, limite de ${WAIT_TIMEOUT}s)"
  echo "$new_plany $new_gateway" >"$PLANY_STATE_DIR/failed"
  # a tag do registry passa a apontar para a imagem de antes e as réplicas voltam, uma por vez
  docker tag "$old_plany" "$(ref_of plany)"
  docker tag "$old_gateway" "$(ref_of plany-gateway)"
  if update_to "$old_plany" && restart_gateway; then
    say "revertido para a versão anterior"
  else
    say "ATENÇÃO: nem a versão anterior ficou saudável"
  fi
  return 1
}

main "$@"
exit $?
