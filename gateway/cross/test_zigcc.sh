#!/bin/sh
# Tests of zigcc-aarch64 and zigar with a fake `zig` that prints what it was given (run: sh gateway/cross/test_zigcc.sh).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '#!/bin/sh\nprintf "%%s\\n" "$@"\n' > "$tmp/zig"
chmod +x "$tmp/zig"
PATH="$tmp:$PATH"
fail=0
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  expected: $2"; echo "  got:      $3"; fail=1; fi
}

got=$("$here/zigcc-aarch64" -c a.c -o a.o | tr '\n' ' ')
check "passes the arguments through, in zig's target and without UBSan" "cc -target aarch64-linux-musl -fno-sanitize=undefined -c a.c -o a.o " "$got"

got=$("$here/zigcc-aarch64" --target=aarch64-unknown-linux-musl -O3 x.c | tr '\n' ' ')
check "drops the --target= that cc-rs adds" "cc -target aarch64-linux-musl -fno-sanitize=undefined -O3 x.c " "$got"

got=$("$here/zigcc-aarch64" "-DNAME=with space" "path with space/x.c" --target=foo | tr '\n' '|')
check "keeps arguments with spaces whole" "cc|-target|aarch64-linux-musl|-fno-sanitize=undefined|-DNAME=with space|path with space/x.c|" "$got"

got=$("$here/zigcc-aarch64" | tr '\n' ' ')
check "no arguments" "cc -target aarch64-linux-musl -fno-sanitize=undefined " "$got"

got=$("$here/zigar" crs lib.a a.o b.o | tr '\n' ' ')
check "zigar hands everything to zig ar" "ar crs lib.a a.o b.o " "$got"

exit $fail
