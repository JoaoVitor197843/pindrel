#!/bin/sh
# The files that MUST DIFFER between the release branch (main) and dev, checked by what is inside them.
#
#   sh .forgejo/scripts/check-branch-files.sh <release|dev> [<git revision>]
#
#   release   the variant of main (and of the tags cut from it)
#   dev       the variant of dev
#   revision  read the files from that commit (what a push carries); without it, from the working tree
#
# Exit 0 when every file is the variant asked for; 1, naming each file, when one is not; 2 for a wrong call.
#
# Why it exists: dev and main are merged both ways, and a merge silently takes the other branch's version of any file that
# only one side changed (the `merge=ours` driver of .gitattributes only runs when both sides changed it, and only in a clone
# that has `git config merge.ours.driver true`). That is how dev lost its own files once and, the other way round, how
# default secrets could reach main. This check does not depend on a clone's settings: the pre-push hook (.githooks), the
# `branch-files` workflow and the `images` job of release.yml all run it.
#
# What each branch holds:
#   file                         release (main)                          dev
#   compose.yml                  DB_PASSWORD, JWT_SECRET: ${VAR:?msg}    ${VAR:-default}: starts with no .env
#   .env.example                 DB_PASSWORD= and JWT_SECRET= blank      both with a value
#   web/src/lib/logo/debug.ts    stub that always returns undefined      ?logo=<theme> forces a theme
#   web/src/lib/logo/debug.test.ts   does not exist                      exists (tests the override)
set -u
# Git for Windows' shell turns "origin/dev:.env.example" into a list of paths; harmless (ignored) anywhere else
export MSYS_NO_PATHCONV=1
variant=${1:-}
rev=${2:-}
case $variant in
  release | dev) ;;
  *)
    echo "usage: sh check-branch-files.sh <release|dev> [<git revision>]" >&2
    exit 2
    ;;
esac
other=dev
[ "$variant" = dev ] && other=release

read_file() { if [ -n "$rev" ]; then git show "$rev:$1" 2>/dev/null; else cat "$1" 2>/dev/null; fi; }
file_exists() { if [ -n "$rev" ]; then git cat-file -e "$rev:$1" 2>/dev/null; else [ -f "$1" ]; fi; }

bad=0
fail() {
  echo "FALHA ($variant) $1: $2"
  bad=1
}
# need FILE REGEX WHY: the file must have a line matching REGEX
need() { read_file "$1" | grep -Eq -- "$2" || fail "$1" "$3"; }
# forbid FILE REGEX WHY: the file must not have a line matching REGEX
forbid() { if read_file "$1" | grep -Eq -- "$2"; then fail "$1" "$3"; fi; }
must_exist() { file_exists "$1" || fail "$1" "$2"; }
must_not_exist() { if file_exists "$1"; then fail "$1" "$2"; fi; }

looks="isto é a versão de $other"
if [ "$variant" = release ]; then
  must_exist compose.yml "não existe"
  need compose.yml 'DB_PASSWORD:\?' "DB_PASSWORD tem de ser obrigatória (\${DB_PASSWORD:?...}); $looks"
  need compose.yml 'JWT_SECRET:\?' "JWT_SECRET tem de ser obrigatória (\${JWT_SECRET:?...}); $looks"
  forbid compose.yml 'DB_PASSWORD:-' "a main não pode ter senha padrão do banco; $looks"
  forbid compose.yml 'JWT_SECRET:-' "a main não pode ter JWT_SECRET padrão; $looks"
  must_exist .env.example "não existe"
  need .env.example '^DB_PASSWORD=$' "DB_PASSWORD tem de estar em branco; $looks"
  need .env.example '^JWT_SECRET=$' "JWT_SECRET tem de estar em branco; $looks"
  must_exist web/src/lib/logo/debug.ts "não existe"
  need web/src/lib/logo/debug.ts 'return undefined' "tem de ser o stub de release (forcedTheme devolve sempre undefined); $looks"
  forbid web/src/lib/logo/debug.ts 'URLSearchParams' "a main não pode forçar o tema pela URL; $looks"
  must_not_exist web/src/lib/logo/debug.test.ts "só existe na dev: testa o override, que na main é um stub"
else
  must_exist compose.yml "não existe"
  need compose.yml 'DB_PASSWORD:-' "DB_PASSWORD tem de ter valor padrão (\${DB_PASSWORD:-...}); $looks"
  need compose.yml 'JWT_SECRET:-' "JWT_SECRET tem de ter valor padrão (\${JWT_SECRET:-...}); $looks"
  forbid compose.yml 'DB_PASSWORD:\?' "a dev sobe sem .env: DB_PASSWORD não pode ser obrigatória; $looks"
  forbid compose.yml 'JWT_SECRET:\?' "a dev sobe sem .env: JWT_SECRET não pode ser obrigatória; $looks"
  must_exist .env.example "não existe"
  need .env.example '^DB_PASSWORD=.+' "DB_PASSWORD tem de ter valor; $looks"
  need .env.example '^JWT_SECRET=.+' "JWT_SECRET tem de ter valor; $looks"
  must_exist web/src/lib/logo/debug.ts "não existe"
  need web/src/lib/logo/debug.ts 'URLSearchParams' "tem de ser o override completo (?logo=<tema>); $looks"
  forbid web/src/lib/logo/debug.ts 'return undefined' "a dev não pode ter o stub de release; $looks"
  must_exist web/src/lib/logo/debug.test.ts "tem de existir na dev: testa o override"
fi

if [ $bad -eq 0 ]; then
  echo "ok: os arquivos específicos são os da variante $variant${rev:+ (em $rev)}"
else
  echo "Os arquivos acima não são os da variante $variant. Restaure a versão certa (git show <commit do ramo certo>:<arquivo>); o ramo $other tem a dele." >&2
fi
exit $bad
