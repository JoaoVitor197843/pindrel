#!/bin/sh
# Tests .forgejo/scripts/github-assets.sh against a fake GitHub (no network):
#   sh .forgejo/scripts/test_github_assets.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
cat >"$work/fake_github.py" <<'PY'
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file = sys.argv[1]
hits = {}  # path -> requests seen


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        n = hits[self.path] = hits.get(self.path, 0) + 1
        # /o/r/releases/download/<tag>/<name>; "late-*" shows up at the 3rd try, "empty-*" is a 200 without a body,
        # "never-*" never exists
        name = self.path.rsplit("/", 1)[-1]
        if name.startswith("never") or (name.startswith("late") and n < 3):
            self.send_response(404); self.end_headers(); return
        body = b"" if name.startswith("empty") else ("content of " + name).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


s = ThreadingHTTPServer(("127.0.0.1", 0), H)
open(port_file, "w").write(str(s.server_address[1]))
s.serve_forever()
PY
python3 "$work/fake_github.py" "$work/port" &
server=$!
trap 'kill $server 2>/dev/null; rm -rf "$work"' EXIT
i=0
while [ ! -s "$work/port" ]; do
  i=$((i + 1)); [ $i -lt 100 ] || { echo "the fake GitHub did not start"; exit 1; }
  sleep 0.1
done
export GITHUB_URL="http://127.0.0.1:$(cat "$work/port")" POLL_SECS=1 WAIT_SECS=5
G="sh $here/github-assets.sh"

fails=0
t=0
check() { desc=$1; shift; t=$((t + 1)); if "$@"; then echo "ok $t - $desc"; else echo "FALHOU $t - $desc"; fails=$((fails + 1)); fi; }
quiet() { "$@" >/dev/null 2>&1; }
fails_with() { ! quiet "$@"; }

out="$work/out"
check "downloads a file that is already there" quiet $G o/r v1.0.0 "$out" pindrel-app_v1.0.0_windows_amd64.zip
check "the content is what the server sent" test "$(cat "$out/pindrel-app_v1.0.0_windows_amd64.zip")" = "content of pindrel-app_v1.0.0_windows_amd64.zip"
check "waits for a file that shows up late" quiet $G o/r v1.0.0 "$out" late-one.zip
check "the late file is complete" test "$(cat "$out/late-one.zip")" = "content of late-one.zip"
check "several files in one call" quiet $G o/r v1.0.0 "$out" a.zip b.zip
check "both arrived" test -s "$out/a.zip" -a -s "$out/b.zip"
check "gives up when the file never shows up" fails_with $G o/r v1.0.0 "$out" never-one.zip
check "no half file is left after giving up" test ! -e "$out/never-one.zip" -a ! -e "$out/never-one.zip.part"
check "an empty body is not a file" fails_with $G o/r v1.0.0 "$out" empty-one.zip
check "an empty file is not left behind" test ! -e "$out/empty-one.zip"
check "one missing file among good ones fails the call" fails_with $G o/r v1.0.0 "$out" a.zip never-two.zip
check "a tag with + and - in it works" quiet $G o/r 'v1.0.0-rc1+b5' "$out" c.zip
check "GitHub unreachable fails after the wait" fails_with env GITHUB_URL=http://127.0.0.1:1 WAIT_SECS=2 $G o/r v1.0.0 "$out" d.zip
check "no files asked for fails" fails_with $G o/r v1.0.0 "$out"
check "missing arguments fail" fails_with $G

echo
if [ "$fails" -eq 0 ]; then echo "todos os $t testes passaram"; else echo "$fails de $t falharam"; exit 1; fi
