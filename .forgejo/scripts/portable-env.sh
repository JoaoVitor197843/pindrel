# Sourced by the shell tests (.forgejo/scripts/test_*.sh, deploy/test_update.sh): what they need from the machine they run on,
# so the same tests pass on Linux, macOS and Windows (Git for Windows' sh) instead of assuming Linux.
#
#   . "$here/portable-env.sh"
#   portable_env "$work"        # a throwaway directory (the shim goes in it)
#   have_flock                  # true when `flock` really locks (util-linux); false on macOS and Git for Windows
#   posix_modes "$work"         # true when the file system keeps POSIX permissions (chmod 640 reads back as 640)

# Python on Windows differs from Python elsewhere in two ways the scripts under test do not expect, and a machine may have
# `python` but no `python3` (Git for Windows). This makes it the same everywhere:
#  - it reads files with the locale's encoding (cp1252) unless told otherwise: UTF-8 mode;
#  - print() ends each line with \r\n, so a `while read name` over its output keeps a \r that breaks the next URL: a
#    sitecustomize.py (found through PYTHONPATH) turns that translation off;
#  - no python3: a `python3` that calls `python`.
portable_env() {
  export PYTHONUTF8=1
  mkdir -p "$1/pyshim"
  printf '%s\n' 'import sys' 'for _s in (sys.stdout, sys.stderr):' '    try:' '        _s.reconfigure(newline="\n")' '    except Exception:' '        pass' >"$1/pyshim/sitecustomize.py"
  sep=:
  (cd "$1" && pwd -W >/dev/null 2>&1) && sep=';' # Python for Windows separates PYTHONPATH with ;
  PYTHONPATH="$(native_path "$1/pyshim")${PYTHONPATH:+$sep$PYTHONPATH}"
  export PYTHONPATH
  command -v python3 >/dev/null 2>&1 && python3 -c 'pass' >/dev/null 2>&1 && return 0
  python -c 'pass' >/dev/null 2>&1 || return 0 # no Python at all: the test fails with its own message
  printf '#!/bin/sh\nexec python "$@"\n' >"$1/pyshim/python3" && chmod +x "$1/pyshim/python3"
  PATH="$1/pyshim:$PATH"
  export PATH
}

have_flock() { command -v flock >/dev/null 2>&1; }

posix_modes() {
  f="$1/.mode-probe"
  : >"$f" && chmod 640 "$f" 2>/dev/null && [ "$(stat -c %a "$f" 2>/dev/null)" = 640 ]
  r=$?
  rm -f "$f"
  return $r
}

# A path as a program that is not part of the shell understands it. Git for Windows' sh turns a path into C:/... when it is a
# whole argument, but not when it sits inside text (python3 -c 'open("/tmp/x")'), where this is needed. Elsewhere: unchanged.
native_path() { (cd "$1" 2>/dev/null && pwd -W 2>/dev/null) || printf '%s\n' "$1"; }
