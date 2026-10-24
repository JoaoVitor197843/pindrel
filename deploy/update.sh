#!/bin/sh
# Updates Plany from the registry: pulls the new images, recreates the containers and waits for them to become
# healthy; if they do not, goes back to the previous images and does not try the same version again.
# Meant to run from a systemd timer (deploy/install-timer.sh). Idempotent: with no new image it does nothing.
#
# Variables (all optional):
#   REGISTRY, REGISTRY_OWNER, PLANY_TAG  where the images come from (same names as compose.registry.yml)
#   COMPOSE_FILE     compose files, separated by `:` (if not set here nor in .env: compose.yml,
#                    compose.lb.yml and compose.registry.yml). A server with its own tweaks (ports, volumes)
#                    puts a compose.<name>.yml at the end and lists everything in the .env's COMPOSE_FILE.
#   PLANY_REPLICAS   API replicas (empty = whatever the compose files define)
#   WAIT_TIMEOUT     seconds to wait for them to become healthy (120)
#   PLANY_STATE_DIR  where to keep the version that failed (./.deploy-state)
#   UPDATE_GIT       1 = first, `git pull --ff-only` to bring compose changes (1)
#
# The body lives in a function and the file ends in `exit`: git pull may swap this file while
# it runs, and sh reads the script piece by piece.

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
  # time of each step in the log, to see where the seconds go on the Pi
  started=$(date +%s); lap_at=$started
  lap() { now=$(date +%s); say "$1: $((now - lap_at))s"; lap_at=$now; }
  compose() { docker compose "$@"; }
  ref_of() { echo "$REGISTRY/$REGISTRY_OWNER/$1:$PLANY_TAG"; }
  # image id of the container running service $1 (empty if there is none)
  running_image() {
    cid=$(compose ps -q "$1" | head -n 1)
    [ -n "$cid" ] && docker inspect -f '{{.Image}}' "$cid" || true
  }


  ids_of() { compose ps -q "$1"; }
  image_of() { docker inspect -f '{{.Image}}' "$1"; }
  health_of() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1"; }
  # API replicas that do NOT run image $1
  stale_of() {
    for c in $(ids_of plany); do
      [ "$(image_of "$c")" = "$1" ] || echo "$c"
    done
  }
  # an `up --wait` fails while any sick replica remains: remove the ones that are not healthy
  purge_unhealthy() {
    for c in $(ids_of plany); do
      case "$(health_of "$c")" in healthy|running) ;; *) docker rm -f "$c" >/dev/null 2>&1 || true ;; esac
    done
  }
  # API rolling update: puts the new replica (image $1) next to the old ones, waits for it to be healthy and only then
  # takes one old one down; repeats until none is left. The old ones keep serving the whole time (the gateway retries a
  # failed connection on another replica) and, if the new one does not come up, no old one was touched.
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
      lap "réplica nova saudável"
      docker stop -t 20 "$stale" >/dev/null 2>&1 || true
      docker rm "$stale" >/dev/null 2>&1 || true
      lap "réplica antiga parada"
    done
    # number of replicas explicitly requested (PLANY_REPLICAS)
    if [ -n "$scale" ]; then compose up -d --no-deps --no-recreate --wait --wait-timeout "$WAIT_TIMEOUT" $scale plany || return 1; fi
    return 0
  }
  # the gateway is a single one (host network, one port): recreating it is the only cut, and only if the image changed
  restart_gateway() { compose up -d --no-deps --wait --wait-timeout "$WAIT_TIMEOUT" gateway; }
  finish_ok() {
    lap "gateway e conferência final"
    rm -f "$PLANY_STATE_DIR/failed"
    docker image prune -f >/dev/null 2>&1 || true
    say "atualizado em $(($(date +%s) - started))s"
  }

  mkdir -p "$PLANY_STATE_DIR"
  # one update at a time (the timer may fire again while one is slow)
  exec 9>"$PLANY_STATE_DIR/lock"
  flock -n 9 || { say "outra atualização está em andamento"; return 0; }

  if [ "$UPDATE_GIT" = 1 ] && [ -d .git ]; then
    git pull --ff-only --quiet || say "aviso: git pull falhou, seguindo com o compose atual"
  fi

  services="plany gateway"
  old_plany=$(running_image plany)
  old_gateway=$(running_image gateway)

  lap "git pull e leitura do estado"
  compose pull --quiet $services || { say "não foi possível baixar as imagens (rede ou login no registry)"; return 1; }
  lap "pull das imagens"

  new_plany=$(docker image inspect -f '{{.Id}}' "$(ref_of plany)")
  new_gateway=$(docker image inspect -f '{{.Id}}' "$(ref_of plany-gateway)")

  # the version is the PAIR of images: an image equal to the failed one, with the other already different, is another version
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
    # first install: there is no serving replica worth protecting
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
  # the registry tag goes back to pointing at the previous image and the replicas return, one at a time
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
