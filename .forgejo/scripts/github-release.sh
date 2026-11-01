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

# forgejo <path>: GET with the Forgejo token
forgejo() { curl -sS --fail-with-body -H "Authorization: token $TOKEN" "$@"; }
# github <method> <url> [curl args...]: prints the body, fails on an HTTP error
github() {
  method=$1 url=$2
  shift 2
  curl -sS --fail-with-body -X "$method" -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" "$@" "$url"
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
  forgejo -L -o "$work/file" "$url"
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
done <"$work/assets.txt"
