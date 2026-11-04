#!/bin/sh
# Tests .forgejo/scripts/dispatch-images.sh against a fake GitHub API (no network):
#   sh .forgejo/scripts/test_dispatch_images.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
cat >"$work/fake_github.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file, log_file = sys.argv[1], sys.argv[2]
seen = {}  # commit sha -> times asked

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, body=b"{}"):
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authorized(self):
        return self.headers.get("Authorization") == "Bearer good-token"

    def do_GET(self):
        # /repos/o/r/commits/<sha>: "aaaa..." is there at once, "bbbb..." from the 3rd ask, "cccc..." never
        sha = self.path.rsplit("/", 1)[-1]
        if not self.authorized():
            return self.reply(401)
        n = seen[sha] = seen.get(sha, 0) + 1
        if sha.startswith("a") or (sha.startswith("b") and n >= 3):
            return self.reply(200)
        self.reply(404)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if not self.authorized():
            return self.reply(401)
        with open(log_file, "a") as f:
            f.write(self.path + " " + body.decode() + "\n")
        if "/nope.yml/" in self.path:
            return self.reply(404, b'{"message":"Not Found"}')
        if "/forbidden.yml/" in self.path:
            return self.reply(403, b'{"message":"Resource not accessible by personal access token"}')
        if "/wrong.yml/" in self.path:
            return self.reply(422, b'{"message":"Workflow does not have workflow_dispatch trigger"}')
        if "/boom.yml/" in self.path:
            return self.reply(500)
        self.reply(204, b"")

s = ThreadingHTTPServer(("127.0.0.1", 0), H)
open(port_file, "w").write(str(s.server_address[1]))
s.serve_forever()
PY
python3 "$work/fake_github.py" "$work/port" "$work/posts" &
server=$!
trap 'kill $server 2>/dev/null; rm -rf "$work"' EXIT
i=0
while [ ! -s "$work/port" ]; do
  i=$((i + 1)); [ $i -lt 100 ] || { echo "the fake GitHub did not start"; exit 1; }
  sleep 0.1
done
export GITHUB_API="http://127.0.0.1:$(cat "$work/port")" GITHUB_REPO=o/r STEP_SECS=0 MAX_TRIES=5 GH_RELEASE_TOKEN=good-token
D="sh $here/dispatch-images.sh"
A=$(printf 'a%.0s' $(seq 1 40)); B=$(printf 'b%.0s' $(seq 1 40)); C=$(printf 'c%.0s' $(seq 1 40))

fails=0
t=0
check() { desc=$1; shift; t=$((t + 1)); if "$@"; then echo "ok $t - $desc"; else echo "FALHOU $t - $desc"; fails=$((fails + 1)); fi; }
quiet() { "$@" >/dev/null 2>&1; }
fails_with() { ! quiet "$@"; }

check "a commit that is already on GitHub starts the build" quiet $D "$A"
check "the dispatch asks for that exact commit on main" grep -q "release-images.yml/dispatches {\"ref\":\"main\",\"inputs\":{\"sha\":\"$A\"}}" "$work/posts"
check "waits for the mirror when the commit shows up late" quiet $D "$B"
check "the late commit was dispatched too" grep -q "\"sha\":\"$B\"" "$work/posts"
posts_before=$(wc -l <"$work/posts")
check "a commit that never arrives fails" fails_with $D "$C"
check "and nothing was dispatched for it" test "$(wc -l <"$work/posts")" = "$posts_before"
check "no token fails" fails_with env GH_RELEASE_TOKEN= $D "$A"
check "a wrong token is refused and not retried forever" fails_with env GH_RELEASE_TOKEN=bad $D "$A"
check "a token without Actions permission says so" sh -c "WORKFLOW=forbidden.yml $D $A 2>&1 | grep -q 'Actions: Read and write'"
check "a missing workflow fails" fails_with env WORKFLOW=nope.yml $D "$A"
check "a workflow without workflow_dispatch fails" fails_with env WORKFLOW=wrong.yml $D "$A"
check "an unexpected answer fails" fails_with env WORKFLOW=boom.yml $D "$A"
check "GitHub unreachable fails" fails_with env GITHUB_API=http://127.0.0.1:1 MAX_TRIES=2 $D "$A"
check "no sha fails" fails_with $D
check "a short sha fails" fails_with $D abc123
check "a sha with strange characters fails" fails_with $D "$(printf 'a%.0s' $(seq 1 39));ls"
check "an injection attempt in the sha is not run" fails_with $D '$(touch /tmp/pwned-dispatch)aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
check "and left nothing behind" test ! -e /tmp/pwned-dispatch

echo
if [ "$fails" -eq 0 ]; then echo "todos os $t testes passaram"; else echo "$fails de $t falharam"; exit 1; fi
