#!/bin/sh
# Tests .forgejo/scripts/github-release.sh against a fake Forgejo and a fake GitHub (no network):
#   sh .forgejo/scripts/test_github_release.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
python3 "$here/fake_forgejo.py" "$work/fport" fg-token &
p1=$!
python3 "$here/fake_github_api.py" "$work/gport" gh-token &
p2=$!
trap 'kill $p1 $p2 2>/dev/null; rm -rf "$work"' EXIT
i=0
while [ ! -s "$work/fport" ] || [ ! -s "$work/gport" ]; do
  i=$((i + 1)); [ $i -lt 100 ] || { echo "the fakes did not start"; exit 1; }
  sleep 0.1
done
F="http://127.0.0.1:$(cat "$work/fport")"
G="http://127.0.0.1:$(cat "$work/gport")"
export API="$F/api/v1/repos/o/r" TOKEN=fg-token GH_REPO=o/r GH_TOKEN=gh-token GITHUB_API="$G" GITHUB_UPLOADS="$G/uploads"
R="sh $here/release.sh"
S="sh $here/github-release.sh"

fails=0
t=0
check() { desc=$1; shift; t=$((t + 1)); if "$@"; then echo "ok $t - $desc"; else echo "FALHOU $t - $desc"; fails=$((fails + 1)); fi; }
quiet() { "$@" >/dev/null 2>&1; }
fails_with() { ! quiet "$@"; }
gstate() { curl -s "$G/_state"; }
# gfield <python expression over d (the GitHub state)>
gfield() { gstate | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
# rel <tag> <python expression over r (that release)>
rel() { gstate | python3 -c "import json,sys; d=json.load(sys.stdin); r=[x for x in d.values() if x['tag_name']=='$1'][0]; print($2)"; }
tag_on_github() { curl -s -X POST -d "{\"tags\": [\"$1\"]}" "$G/_tags" >/dev/null; }

printf 'Notas da versão\ncom "aspas" e acentuação: ção\n' >"$work/notes.md"
printf 'apk-bytes-1' >"$work/plany_v1.0.0_android.apk"
printf 'gateway-bytes' >"$work/plany-gateway_v1.0.0_linux_arm64.tar.gz"
printf 'win' >"$work/plany-app_v1.0.0_windows_amd64.zip"

$R create v1.0.0 "$work/notes.md" >/dev/null
$R upload v1.0.0 "$work/plany_v1.0.0_android.apk" "$work/plany-gateway_v1.0.0_linux_arm64.tar.gz" "$work/plany-app_v1.0.0_windows_amd64.zip" >/dev/null
$R publish v1.0.0 >/dev/null

check "a tag that GitHub does not have yet fails" fails_with $S v1.0.0
check "and creates nothing there" test "$(gfield 'len(d)')" = 0

tag_on_github v1.0.0
check "copies the release when the tag is on GitHub" quiet $S v1.0.0
check "the notes are the Forgejo ones, intact" test "$(rel v1.0.0 'r["body"] == open("'"$work"'/notes.md").read()')" = True
check "it is a public release, not a pre-release" test "$(rel v1.0.0 'r["draft"], r["prerelease"]')" = "False False"
check "the APK and the gateway arrive, with their .sha256" \
  test "$(rel v1.0.0 'sorted(a["name"] for a in r["assets"])')" = "['plany-gateway_v1.0.0_linux_arm64.tar.gz', 'plany-gateway_v1.0.0_linux_arm64.tar.gz.sha256', 'plany_v1.0.0_android.apk', 'plany_v1.0.0_android.apk.sha256']"
check "the Windows zip is not copied (it comes from GitHub)" test "$(rel v1.0.0 'any("windows" in a["name"] for a in r["assets"])')" = False
check "the content is exactly what Forgejo has" \
  test "$(rel v1.0.0 '[a["data"] for a in r["assets"] if a["name"].endswith(".apk")][0]')" = "apk-bytes-1"

printf 'apk-bytes-2' >"$work/plany_v1.0.0_android.apk"
$R upload v1.0.0 "$work/plany_v1.0.0_android.apk" >/dev/null
check "a re-run refreshes a file that changed, with no duplicate error" quiet $S v1.0.0
check "one copy of the APK, with the new content" \
  test "$(rel v1.0.0 'len([a for a in r["assets"] if a["name"].endswith(".apk")]), [a["data"] for a in r["assets"] if a["name"]=="plany_v1.0.0_android.apk"][0]')" = "1 apk-bytes-2"
check "still only one release" test "$(gfield 'len(d)')" = 1

# GitHub already has the release (release-desktop.yml made it with the Windows zip): reused, that file untouched
printf 'Outras notas\n' >"$work/notes2.md"
printf 'linux' >"$work/plany-app_v1.1.0-rc1_linux_amd64.tar.gz"
$R create v1.1.0-rc1 "$work/notes2.md" >/dev/null
$R upload v1.1.0-rc1 "$work/plany-app_v1.1.0-rc1_linux_amd64.tar.gz" >/dev/null
tag_on_github v1.1.0-rc1
curl -s -X POST -H "Authorization: Bearer gh-token" -d '{"tag_name": "v1.1.0-rc1", "name": "x", "body": "feito no GitHub", "prerelease": true}' "$G/repos/o/r/releases" >/dev/null
rid=$(rel v1.1.0-rc1 'r["id"]')
curl -s -X POST -H "Authorization: Bearer gh-token" --data-binary 'win-from-github' "$G/uploads/repos/o/r/releases/$rid/assets?name=plany-app_v1.1.0-rc1_windows_amd64.zip" >/dev/null
check "reuses the release GitHub already made" quiet $S v1.1.0-rc1
check "no second release was made" test "$(gfield 'len(d)')" = 2
check "the Windows file GitHub built is untouched" \
  test "$(rel v1.1.0-rc1 '[a["data"] for a in r["assets"] if "windows" in a["name"]][0]')" = "win-from-github"
check "the notes became the Forgejo ones" test "$(rel v1.1.0-rc1 'r["body"]')" = "Outras notas"
check "a tag with a dash stays a pre-release" test "$(rel v1.1.0-rc1 'r["prerelease"]')" = True

# a release with no files at all is fine
printf 'sem arquivos\n' >"$work/notes3.md"
$R create v1.2.0 "$work/notes3.md" >/dev/null
tag_on_github v1.2.0
check "a Forgejo release without files is copied as notes only" quiet $S v1.2.0
check "and has no files on GitHub" test "$(rel v1.2.0 'len(r["assets"])')" = 0

check "no Forgejo release for the tag fails" fails_with $S v9.9.9
check "a wrong Forgejo token fails" fails_with env TOKEN=wrong $S v1.0.0
check "a wrong GitHub token fails" fails_with env GH_TOKEN=wrong $S v1.0.0
check "GitHub down fails instead of pretending" fails_with env GITHUB_API=http://127.0.0.1:1 $S v1.0.0
check "no GitHub token set fails" fails_with env -u GH_TOKEN $S v1.0.0
check "no tag given fails" fails_with $S

echo
if [ "$fails" -eq 0 ]; then echo "todos os $t testes passaram"; else echo "$fails de $t falharam"; exit 1; fi
