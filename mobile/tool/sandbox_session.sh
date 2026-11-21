# Drives the REAL app, in a sandbox that is not the person's own data, with real mouse and keyboard events (xdotool, through XWayland).
#   fvm flutter build linux --release && cp -r build/linux/x64/release/bundle /tmp/pindrel_app
#   SEED_DB=/tmp/sandbox/normal/data/com.pindrel.app/notes.db SEED=normal fvm flutter test tool/seed_notes_test.dart   (SEED=heavy: 3000 pages)
#   source tool/sandbox_session.sh; sbx_start normal; sbx_attach; sbx_click 503 366; sbx_shot name; sbx_ram "label"; sbx_stop
# Each Bash call forgets the variables: call sbx_attach first. HOME and XDG_* point into /tmp/sandbox/<profile>, so the real notes.db is never opened.
# usage: source /tmp/sbx.sh; sbx_start empty|normal|heavy ; sbx_shot name ; sbx_ram label
sbx_start() {
  local p=$1
  export SBX=/tmp/sandbox/$p
  (HOME=$SBX XDG_DATA_HOME=$SBX/data XDG_CONFIG_HOME=$SBX/config XDG_CACHE_HOME=$SBX/cache GDK_BACKEND=x11 nohup /tmp/pindrel_app/Pindrel >/tmp/sbx_$p.log 2>&1 &)
  sleep 6
  SBX_PID=$(pgrep -f "^/tmp/pindrel_app/Pindrel" | head -1)
  SBX_WID=$(for w in $(xdotool search --onlyvisible --class pindrel); do [ "$(xdotool getwindowpid $w)" = "$SBX_PID" ] && echo $w; done | tail -1)
  xdotool windowsize $SBX_WID 1180 820; xdotool windowmove $SBX_WID 40 40; sleep 0.8
  eval "$(xdotool getwindowgeometry --shell $SBX_WID)"; SBX_X=$X; SBX_Y=$Y
  export SBX_PID SBX_WID SBX_X SBX_Y
}
sbx_shot() { sleep 0.7; import -window $SBX_WID /tmp/sbx_$1.png; }
sbx_click() { xdotool mousemove $((SBX_X + $1)) $((SBX_Y + $2)) click ${3:-1}; sleep ${4:-0.6}; }
sbx_ram() { awk -v l="$1" '/^Pss:/{p=$2} /^Rss:/{r=$2} END{printf "%-38s PSS %6.1f MB   RSS %6.1f MB\n", l, p/1024, r/1024}' /proc/$SBX_PID/smaps_rollup; }
sbx_stop() { kill $SBX_PID 2>/dev/null; sleep 1; }
sbx_attach() {
  SBX_PID=$(pgrep -f "^/tmp/pindrel_app/Pindrel" | head -1)
  SBX_WID=$(for w in $(xdotool search --onlyvisible --class pindrel); do [ "$(xdotool getwindowpid $w)" = "$SBX_PID" ] && echo $w; done | tail -1)
  eval "$(xdotool getwindowgeometry --shell $SBX_WID)"; SBX_X=$X; SBX_Y=$Y
}
