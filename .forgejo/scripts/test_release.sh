#!/bin/sh
# Tests .forgejo/scripts/release.sh against a fake Forgejo API (no network):
#   sh .forgejo/scripts/test_release.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
python3 "$here/fake_forgejo.py" "$work/port" s3cret &
server=$!
trap 'kill $server 2>/dev/null; rm -rf "$work"' EXIT
i=0
while [ ! -s "$work/port" ]; do
  i=$((i + 1))
  [ $i -lt 100 ] || { echo "the fake API did not start"; exit 1; }
  sleep 0.1
done
export API="http://127.0.0.1:$(cat "$work/port")/api/v1/repos/o/r"
export TOKEN=s3cret
R="sh $here/release.sh"

fails=0
t=0
check() { # check "description" command...
  desc=$1; shift
  t=$((t + 1))
  if "$@"; then echo "ok $t - $desc"; else echo "FALHOU $t - $desc"; fails=$((fails + 1)); fi
}
state() { curl -s "http://127.0.0.1:$(cat "$work/port")/_state"; }
# field <python expression over d (the state)>
field() { state | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
fails_with() { ! "$@" >/dev/null 2>&1; }

printf 'primeira linha\nsegunda com "aspas", \\ barra e acentuação: ção\n' >"$work/notes.md"
printf 'binary-one' >"$work/a.tar.gz"
printf 'binary-two' >"$work/b.apk"

id=$($R create v1.0.0 "$work/notes.md")
check "create makes a draft release and prints its id" test "$id" = 1
check "the draft is not public and not a pre-release" test "$(field 'd["1"]["draft"], d["1"]["prerelease"]')" = "True False"
check "notes with quotes, backslashes, newlines and accents arrive intact" \
  test "$(field 'd["1"]["body"] == open("'"$work"'/notes.md").read()')" = True
check "create twice reuses the release" test "$($R create v1.0.0 "$work/notes.md")" = 1
check "a tag with a dash is a pre-release" sh -c "$R create v1.1.0-rc1 '$work/notes.md' >/dev/null && test \"\$(curl -s http://127.0.0.1:$(cat "$work/port")/_state | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"2\"][\"prerelease\"])')\" = True"

$R upload v1.0.0 "$work/a.tar.gz" "$work/b.apk" >/dev/null
check "each file and its .sha256 are attached" \
  test "$(field 'sorted(a["name"] for a in d["1"]["assets"])')" = "['a.tar.gz', 'a.tar.gz.sha256', 'b.apk', 'b.apk.sha256']"
check "the file content is what was uploaded" \
  test "$(field '"binary-one" in [a["raw"] for a in d["1"]["assets"] if a["name"]=="a.tar.gz"][0]')" = True
check "the checksum file is the sha256 of the file" \
  test "$(cd "$work" && cat a.tar.gz.sha256)" = "$(cd "$work" && sha256sum a.tar.gz)"

printf 'binary-one-v2' >"$work/a.tar.gz"
check "uploading the same name again replaces it, no duplicate error" sh -c "$R upload v1.0.0 '$work/a.tar.gz' >/dev/null"
check "after the re-upload there is one a.tar.gz, with the new content" \
  test "$(field 'len([a for a in d["1"]["assets"] if a["name"]=="a.tar.gz"]), [a["raw"] for a in d["1"]["assets"] if a["name"]=="a.tar.gz"][0].count("binary-one-v2")')" = "1 1"
check "the other files stayed" test "$(field 'len(d["1"]["assets"])')" = 4

check "publish turns the draft public" sh -c "$R publish v1.0.0 >/dev/null && test \"\$(curl -s http://127.0.0.1:$(cat "$work/port")/_state | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"1\"][\"draft\"])')\" = False"

check "upload to a tag without release fails" fails_with $R upload v9.9.9 "$work/a.tar.gz"
check "publish of a tag without release fails" fails_with $R publish v9.9.9
check "upload of a file that does not exist fails" fails_with $R upload v1.0.0 "$work/nope.bin"
check "a wrong token fails" fails_with env TOKEN=wrong $R create v2.0.0 "$work/notes.md"
check "a wrong token created nothing" test "$(field 'len(d)')" = 2
check "no API set fails" fails_with env -u API $R create v2.0.0 "$work/notes.md"
check "an unknown command fails" fails_with $R frobnicate
check "an API that is down fails instead of pretending" fails_with env API=http://127.0.0.1:1/x $R create v3.0.0 "$work/notes.md"

# the tag name goes into URLs and JSON: odd ones must not break or inject
check "a tag with odd characters is created as is" sh -c "$R create 'v1.0.0+build.5' '$work/notes.md' >/dev/null"

echo
if [ "$fails" -eq 0 ]; then echo "todos os $t testes passaram"; else echo "$fails de $t falharam"; exit 1; fi
