#!/bin/sh
# Tests .forgejo/scripts/check-branch-files.sh on small fixtures in a throwaway git repository (no network):
#   sh .forgejo/scripts/test_check_branch_files.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
script="$here/check-branch-files.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1
git init -q . && git config user.email t@t && git config user.name t
mkdir -p web/src/lib/logo

fails=0
t=0
check() { # check "description" command...
  desc=$1; shift
  t=$((t + 1))
  if "$@"; then echo "ok $t - $desc"; else echo "FALHOU $t - $desc"; fails=$((fails + 1)); fi
}
passes() { sh "$script" "$@" >/dev/null 2>&1; }
fails_with() { ! sh "$script" "$@" >/dev/null 2>&1; }
# says <text> <args...>: the output of the check mentions <text>
says() { text=$1; shift; sh "$script" "$@" 2>&1 | grep -q -- "$text"; }

put_release() {
  printf '%s\n' '      - DB_PASSWORD=${DB_PASSWORD:?DB_PASSWORD is required}' '      - JWT_SECRET=${JWT_SECRET:?JWT_SECRET is required}' >compose.yml
  printf '%s\n' 'DB_USER=dev' 'DB_PASSWORD=' 'JWT_SECRET=' >.env.example
  printf '%s\n' 'export function forcedTheme(_search: string) {' '  return undefined' '}' >web/src/lib/logo/debug.ts
  rm -f web/src/lib/logo/debug.test.ts
}
put_dev() {
  printf '%s\n' '      - DB_PASSWORD=${DB_PASSWORD:-change_me}' '      - JWT_SECRET=${JWT_SECRET:-change_me_to_a_long_random_string}' >compose.yml
  printf '%s\n' 'DB_USER=dev' 'DB_PASSWORD=change_me' 'JWT_SECRET=change_me_to_a_long_random_string' >.env.example
  printf '%s\n' 'export function forcedTheme(search: string) {' '  return new URLSearchParams(search).get("logo")' '}' >web/src/lib/logo/debug.ts
  printf '%s\n' "it('forces a theme')" >web/src/lib/logo/debug.test.ts
}

put_release
check "the release files pass as release" passes release
check "the release files fail as dev" fails_with dev
put_dev
check "the dev files pass as dev" passes dev
check "the dev files fail as release" fails_with release

# one file of the other branch is enough to fail, and the message names it
put_release
printf '%s\n' '      - DB_PASSWORD=${DB_PASSWORD:-change_me}' '      - JWT_SECRET=${JWT_SECRET:?x}' >compose.yml
check "release: a default password in compose.yml fails" fails_with release
check "release: ...and the message names compose.yml and the variable" says "compose.yml: a main não pode ter senha padrão" release
put_release; printf '%s\n' 'DB_PASSWORD=change_me' 'JWT_SECRET=' >.env.example
check "release: a filled .env.example secret fails" fails_with release
put_release; printf '%s\n' 'export function forcedTheme(s: string) {' '  return new URLSearchParams(s).get("logo")' '}' >web/src/lib/logo/debug.ts
check "release: the full debug override fails" fails_with release
put_release; echo "it('x')" >web/src/lib/logo/debug.test.ts
check "release: debug.test.ts must not exist" fails_with release

put_dev; printf '%s\n' '      - DB_PASSWORD=${DB_PASSWORD:?required}' '      - JWT_SECRET=${JWT_SECRET:-x}' >compose.yml
check "dev: a required secret in compose.yml fails" fails_with dev
put_dev; printf '%s\n' 'DB_PASSWORD=' 'JWT_SECRET=x' >.env.example
check "dev: a blank .env.example secret fails" fails_with dev
put_dev; printf '%s\n' 'export function forcedTheme(_s: string) {' '  return undefined' '}' >web/src/lib/logo/debug.ts
check "dev: the release stub fails" fails_with dev
put_dev; rm web/src/lib/logo/debug.test.ts
check "dev: debug.test.ts must exist" fails_with dev
put_dev; rm compose.yml
check "a missing file fails" fails_with dev

# reading a commit instead of the working tree (what the pre-push hook does)
put_release; git add -A && git commit -qm release
put_dev # the working tree now holds the dev files, uncommitted
check "revision: HEAD holds the release files" passes release HEAD
check "revision: ...and not the dev files" fails_with dev HEAD
check "working tree: holds the dev files" passes dev
check "working tree: ...and not the release files" fails_with release
check "revision of a commit that does not exist fails" fails_with release deadbeef

# wrong calls
check "no argument is a wrong call (2)" sh -c "sh '$script' >/dev/null 2>&1; [ \$? -eq 2 ]"
check "an unknown variant is a wrong call (2)" sh -c "sh '$script' staging >/dev/null 2>&1; [ \$? -eq 2 ]"

echo
if [ $fails -eq 0 ]; then echo "todos os $t testes passaram"; else echo "$fails de $t falharam"; fi
exit $fails
