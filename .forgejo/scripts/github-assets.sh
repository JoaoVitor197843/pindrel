#!/bin/sh
# Waits for files of a GitHub release and downloads them (for release-tag.yml: the Windows and macOS builds are made
# by GitHub Actions, which takes a while after the tag arrives through the mirror).
#
#   github-assets.sh <owner/repo> <tag> <dir> <file>...
#
# Environment: GITHUB_URL (default https://github.com), WAIT_SECS (total wait per file, default 2700),
# POLL_SECS (pause between tries, default 60). Direct download URLs are used on purpose: unlike the API they have no
# low rate limit for anonymous requests, and the repository is public.
set -eu

repo=${1:?usage: github-assets.sh <owner/repo> <tag> <dir> <file>...}
tag=${2:?missing tag}
dir=${3:?missing dir}
shift 3
[ $# -gt 0 ] || { echo "no files asked for" >&2; exit 1; }

base=${GITHUB_URL:-https://github.com}
wait_secs=${WAIT_SECS:-2700}
poll=${POLL_SECS:-60}
mkdir -p "$dir"

for name in "$@"; do
  deadline=$(( $(date +%s) + wait_secs ))
  while :; do
    rm -f "$dir/$name.part"
    # -f: a 404 (not built yet) is a failure to retry, not a file to keep
    if curl -sSfL -o "$dir/$name.part" "$base/$repo/releases/download/$tag/$name" 2>/dev/null && [ -s "$dir/$name.part" ]; then
      mv "$dir/$name.part" "$dir/$name"
      echo "downloaded $name ($(wc -c <"$dir/$name") bytes)"
      break
    fi
    rm -f "$dir/$name.part"
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "gave up on $name: it did not show up in the GitHub release $tag within ${wait_secs}s" >&2
      exit 1
    fi
    sleep "$poll"
  done
done
