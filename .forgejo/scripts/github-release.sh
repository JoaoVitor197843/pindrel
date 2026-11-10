#!/bin/sh
# Copies the Forgejo release of a tag to the public GitHub repository, which is the downloads page: same notes, same
# files. The Forgejo stays the source of truth; what GitHub holds is a copy that a re-run simply refreshes.
#
#   github-release.sh <tag>
#
# Environment: API and TOKEN (the Forgejo, as in release.sh), GH_REPO (owner/name) and GH_TOKEN (a GitHub token with
# Contents: read and write on that repository), GITHUB_API (default https://api.github.com) and GITHUB_UPLOADS
# (default https://uploads.github.com).
#
# The Windows and macOS zips are skipped: they come FROM GitHub (release-desktop.yml) and are already there.
# The tag must already be on GitHub (the mirror carries it): creating a release for an unknown tag makes GitHub create
# the tag itself, from the default branch.
set -eu

: "${API:?API is not set}"
: "${TOKEN:?TOKEN is not set}"
: "${GH_REPO:?GH_REPO is not set}"
: "${GH_TOKEN:?GH_TOKEN is not set}"
tag=${1:?usage: github-release.sh <tag>}
gh_api=${GITHUB_API:-https://api.github.com}
gh_up=${GITHUB_UPLOADS:-https://uploads.github.com}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# http <auth header> <method> <url> [curl args...]: prints the body on success. On an HTTP error it prints the call and
# the answer's body to stderr (the log used to show only "curl: (22) ... 403", with no way to tell which call it was) and
# fails. A 403/429 that GitHub gives as a rate limit is waited out (Retry-After, else RETRY_SECS) and tried again
# RETRIES times; the Authorization header is never printed.
http() {
  hdr=$1 method=$2 url=$3
  shift 3
  tries=0
  while :; do
    code=$(curl -sS -o "$work/body" -D "$work/headers" -w '%{http_code}' -X "$method" -H "$hdr" "$@" "$url") || code=000
    case $code in 2?? | 3??) cat "$work/body"; return 0 ;; esac
    if { [ "$code" = 403 ] || [ "$code" = 429 ]; } && [ "$tries" -lt "${RETRIES:-3}" ] \
      && grep -qiE 'rate limit|abuse|retry-after' "$work/body" "$work/headers" 2>/dev/null; then
      wait=$(sed -n 's/^[Rr]etry-[Aa]fter: *\([0-9]*\).*/\1/p' "$work/headers" | tail -n 1)
      wait=${wait:-${RETRY_SECS:-60}}
      echo "rate limited ($code) on $method $url: waiting ${wait}s" >&2
      sleep "$wait"
      tries=$((tries + 1))
      continue
    fi
    echo "HTTP $code on $method $url" >&2
    head -c 1000 "$work/body" >&2; echo >&2
    return 1
  done
}
# forgejo <path>: GET with the Forgejo token
forgejo() { http "Authorization: token $TOKEN" GET "$@"; }
# github <method> <url> [curl args...]: prints the body, fails on an HTTP error
github() { http "Authorization: Bearer $GH_TOKEN" "$@"; }
# download <url> <file>: a Forgejo attachment (follows the redirect to the storage)
download() {
  code=$(curl -sS -L -o "$2" -w '%{http_code}' -H "Authorization: token $TOKEN" "$1") || code=000
  case $code in 2??) return 0 ;; esac
  echo "HTTP $code on GET $1 (download)" >&2
  return 1
}
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

forgejo "$API/releases/tags/$tag" >"$work/forgejo.json" || { echo "no Forgejo release for $tag" >&2; exit 1; }

# the tag has to be on GitHub already
code=$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $GH_TOKEN" "$gh_api/repos/$GH_REPO/git/ref/tags/$tag")
[ "$code" = 200 ] || { echo "tag $tag is not on GitHub yet (HTTP $code): is the mirror syncing?" >&2; exit 1; }

# the notes, the name and the pre-release flag of the Forgejo release
python3 - "$tag" "$work/forgejo.json" >"$work/payload.json" <<'PY'
import json, sys
tag, f = sys.argv[1], sys.argv[2]
r = json.load(open(f))
print(json.dumps({"tag_name": tag, "name": tag, "body": r.get("body") or "", "prerelease": bool(r.get("prerelease")), "draft": False}))
PY

# GitHub may have the release already (release-desktop.yml creates it with the Windows and macOS zips)
body=$(curl -sS -w '\n%{http_code}' -H "Authorization: Bearer $GH_TOKEN" "$gh_api/repos/$GH_REPO/releases/tags/$tag")
code=$(printf '%s' "$body" | tail -n 1)
if [ "$code" = 200 ]; then
  id=$(printf '%s' "$body" | sed '$d' | json 'd["id"]')
  github PATCH "$gh_api/repos/$GH_REPO/releases/$id" -d @"$work/payload.json" >/dev/null
elif [ "$code" = 404 ]; then
  id=$(github POST "$gh_api/repos/$GH_REPO/releases" -d @"$work/payload.json" | json 'd["id"]')
else
  echo "GitHub release lookup failed: HTTP $code" >&2
  exit 1
fi

# one line per Forgejo file: <download url> <name>
python3 - "$work/forgejo.json" >"$work/assets.txt" <<'PY'
import json, sys
for a in json.load(open(sys.argv[1])).get("assets", []):
    print(a["browser_download_url"], a["name"])
PY

while read -r url name; do
  case $name in *_windows_* | *_macos_*) echo "skipped $name (built on GitHub)"; continue ;; esac
  download "$url" "$work/file"
  # a re-run replaces a file of the same name instead of failing on the duplicate
  old=$(github GET "$gh_api/repos/$GH_REPO/releases/$id/assets?per_page=100" | python3 -c '
import json, sys
for a in json.load(sys.stdin):
    if a["name"] == sys.argv[1]:
        print(a["id"])
' "$name")
  for oid in $old; do github DELETE "$gh_api/repos/$GH_REPO/releases/assets/$oid" >/dev/null; done
  github POST "$gh_up/repos/$GH_REPO/releases/$id/assets?name=$name" -H 'Content-Type: application/octet-stream' --data-binary @"$work/file" >/dev/null
  echo "uploaded $name"
  sleep "${PAUSE_SECS:-1}" # GitHub's secondary rate limit punishes bursts of writes
done <"$work/assets.txt"
