#!/bin/sh
# Talks to the Forgejo releases API for release-tag.yml.
#
#   release.sh create <tag> <notes-file>   draft release for <tag> (reuses it when it already exists); prints its id
#   release.sh upload <tag> <file>...      attaches each file and its .sha256 (replaces a file of the same name)
#   release.sh publish <tag>               turns the draft into a public release
#
# Environment: API (https://host/api/v1/repos/<owner>/<repo>) and TOKEN (needs write access to the repository).
# A release stays a draft until every build has uploaded its files, so nobody sees half of one.
set -eu

: "${API:?API is not set}"
: "${TOKEN:?TOKEN is not set}"

# api <method> <path> [curl args...]: prints the body, fails on an HTTP error
api() {
  method=$1 path=$2
  shift 2
  curl -sS --fail-with-body -X "$method" -H "Authorization: token $TOKEN" "$@" "$API$path"
}

# json <python expression over d>: reads JSON on stdin
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

# release_id <tag>: empty when there is no release for the tag
release_id() {
  # a 404 is the normal "not yet" answer, so no --fail here
  body=$(curl -sS -H "Authorization: token $TOKEN" -w '\n%{http_code}' "$API/releases/tags/$1")
  code=$(printf '%s' "$body" | tail -n 1)
  [ "$code" = 200 ] && printf '%s' "$body" | sed '$d' | json 'd["id"]'
  [ "$code" = 200 ] || [ "$code" = 404 ] || { echo "release lookup failed: HTTP $code" >&2; return 1; }
  return 0
}

need_release() {
  id=$(release_id "$1")
  [ -n "$id" ] || { echo "no release for $1: run 'create' first" >&2; exit 1; }
  printf '%s' "$id"
}

cmd=${1:?usage: release.sh create|upload|publish ...}
shift

case $cmd in
create)
  tag=$1 notes=$2
  id=$(release_id "$tag")
  if [ -z "$id" ]; then
    # a tag such as v1.2.0-rc1 is a pre-release
    pre=false
    case $tag in *-*) pre=true ;; esac
    payload=$(python3 -c '
import json, sys
tag, notes, pre = sys.argv[1], open(sys.argv[2]).read(), sys.argv[3] == "true"
print(json.dumps({"tag_name": tag, "name": tag, "body": notes, "draft": True, "prerelease": pre}))
' "$tag" "$notes" "$pre")
    id=$(api POST /releases -H 'Content-Type: application/json' -d "$payload" | json 'd["id"]')
  fi
  echo "$id"
  ;;
upload)
  tag=$1
  shift
  id=$(need_release "$tag")
  for file in "$@"; do
    [ -f "$file" ] || { echo "not a file: $file" >&2; exit 1; }
    dir=$(dirname "$file") name=$(basename "$file")
    (cd "$dir" && sha256sum "$name" >"$name.sha256")
    for asset in "$name" "$name.sha256"; do
      # a re-run replaces what it uploaded before instead of failing on the duplicate name
      old=$(api GET "/releases/$id/assets" | python3 -c '
import json, sys
for a in json.load(sys.stdin):
    if a["name"] == sys.argv[1]:
        print(a["id"])
' "$asset")
      for oid in $old; do api DELETE "/releases/$id/assets/$oid" >/dev/null; done
      api POST "/releases/$id/assets?name=$asset" -F "attachment=@$dir/$asset" >/dev/null
      echo "uploaded $asset"
    done
  done
  ;;
publish)
  id=$(need_release "$1")
  api PATCH "/releases/$id" -H 'Content-Type: application/json' -d '{"draft": false}' >/dev/null
  echo "published $1"
  ;;
*)
  echo "unknown command: $cmd" >&2
  exit 1
  ;;
esac
