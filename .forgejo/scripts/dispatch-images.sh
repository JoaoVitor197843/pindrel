#!/bin/sh
# Starts the image build on GitHub (.github/workflows/release-images.yml) for one commit, once the Forgejo tests passed.
#
#   GH_RELEASE_TOKEN=... sh .forgejo/scripts/dispatch-images.sh <full commit sha>
#
# GitHub cannot reach the Forgejo (it only exists on the Tailscale network), so the Forgejo calls GitHub instead: it waits
# for the push mirror to bring the commit over, then asks GitHub to run the workflow on that exact commit. The token is a
# fine-grained GitHub token for this repository with "Contents: read and write" (the release copy) and "Actions: read and
# write" (this call).
#
# Environment (all optional but the token): GITHUB_REPO, GITHUB_API, MAX_TRIES (45), STEP_SECS (20), WORKFLOW.
set -eu

sha=${1:-}
case $sha in
  *[!0-9a-f]* | "") echo "dispatch-images: uso: dispatch-images.sh <sha completo do commit>" >&2; exit 2 ;;
esac
[ "${#sha}" -eq 40 ] || { echo "dispatch-images: o sha precisa ter 40 caracteres" >&2; exit 2; }

repo=${GITHUB_REPO:-JoaoVitor197843/pindrel}
api=${GITHUB_API:-https://api.github.com}
workflow=${WORKFLOW:-release-images.yml}
tries=${MAX_TRIES:-45}
step=${STEP_SECS:-20}
token=${GH_RELEASE_TOKEN:-}
[ -n "$token" ] || { echo "dispatch-images: falta o secret GH_RELEASE_TOKEN" >&2; exit 1; }

resp=$(mktemp)
trap 'rm -f "$resp"' EXIT

call() { # call <method> <url> [json body] -> prints the HTTP status ("000" when nothing answered)
  m=$1; u=$2; b=${3:-}
  if [ -n "$b" ]; then
    curl -s -o "$resp" -w '%{http_code}' -m 30 -X "$m" -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" -d "$b" "$u" || printf '000'
  else
    curl -s -o "$resp" -w '%{http_code}' -m 30 -X "$m" -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" "$u" || printf '000'
  fi
}

# 1. the mirror must have brought the commit
n=0
while :; do
  code=$(call GET "$api/repos/$repo/commits/$sha")
  [ "$code" = 200 ] && break
  case $code in
    401 | 403) echo "dispatch-images: o GitHub recusou o token ($code): confira o GH_RELEASE_TOKEN" >&2; exit 1 ;;
  esac
  n=$((n + 1))
  if [ "$n" -ge "$tries" ]; then
    echo "dispatch-images: o commit $sha não chegou ao GitHub (última resposta: $code); o espelho do Forgejo sincronizou?" >&2
    exit 1
  fi
  sleep "$step"
done
echo "dispatch-images: o commit $sha já está no GitHub"

# 2. start the workflow on exactly that commit (the workflow file is read from main, the code is checked out at the sha)
code=$(call POST "$api/repos/$repo/actions/workflows/$workflow/dispatches" "{\"ref\":\"main\",\"inputs\":{\"sha\":\"$sha\"}}")
case $code in
  204) echo "dispatch-images: build das imagens iniciado no GitHub para $sha" ;;
  401 | 403 | 404)
    echo "dispatch-images: o GitHub recusou o disparo ($code). O token precisa de 'Actions: Read and write' neste repositório:" >&2
    cat "$resp" >&2; echo >&2
    exit 1 ;;
  422)
    echo "dispatch-images: o GitHub não aceitou o disparo (422): o workflow $workflow precisa estar na main do GitHub, com 'workflow_dispatch' e a entrada 'sha'" >&2
    cat "$resp" >&2; echo >&2
    exit 1 ;;
  *) echo "dispatch-images: resposta inesperada do GitHub ($code)" >&2; cat "$resp" >&2; echo >&2; exit 1 ;;
esac
