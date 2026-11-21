#!/usr/bin/env bash
# Drives the real app with real wheel events (xdotool, through XWayland) and reads what the frames cost.
#   tool/scroll_probe.sh MODE SIZE SECONDS [wrapper command...]
# e.g. tool/scroll_probe.sh today std 20 systemd-run --user --scope -p AllowedCPUs=0 -p CPUQuota=50% -p CPUQuotaPeriodSec=5ms
# needs a build of tool/mem_table.dart and a display; the pointer is taken over for the length of the run.
set -u
cd "$(dirname "$0")/.."
mode=${1:-today}; size=${2:-std}; secs=${3:-20}; shift 3 || true
out=${OUT:-/tmp/scroll_probe.jsonl}
GDK_BACKEND=x11 DRIVE=external MODE=$mode SIZE=$size PROBE_SECONDS=$secs OUT=$out "$@" build/linux/x64/release/bundle/Pindrel >/dev/null 2>&1 &
app=$!
sleep 5
wid=""
for _ in $(seq 1 20); do
  wid=$(xdotool search --onlyvisible --name . 2>/dev/null | while read -r w; do
    if [ "$(xdotool getwindowpid "$w" 2>/dev/null)" = "$(pgrep -P "$app" -n 2>/dev/null || echo $app)" ] || [ "$(xdotool getwindowpid "$w" 2>/dev/null)" = "$app" ]; then echo "$w"; fi
  done | tail -1)
  [ -n "$wid" ] && break
  sleep 0.5
done
if [ -z "$wid" ]; then wid=$(xdotool search --onlyvisible --class pindrel 2>/dev/null | tail -1); fi
[ -z "$wid" ] && { echo "no window"; kill $app 2>/dev/null; exit 1; }
eval "$(xdotool getwindowgeometry --shell "$wid")"
xdotool mousemove $((X + WIDTH / 2)) $((Y + HEIGHT / 2))
t0=$(date +%s)
while kill -0 "$app" 2>/dev/null && [ $(( $(date +%s) - t0 )) -lt $((secs)) ]; do
  xdotool click --repeat 30 --delay ${DELAY:-50} 5
  xdotool click --repeat 30 --delay ${DELAY:-50} 4
done
wait "$app" 2>/dev/null
tail -1 "$out"
