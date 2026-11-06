#!/usr/bin/env bash
# XTEST events enter the GTK host through X11; MBUI_DRIVE is not used. Each wait is for the app's own input log.
set -euo pipefail
mkdir -p out/host
log=out/host/modifiers.log
: > "$log"
MBUI_BENCH=-1 MBUI_WIN=960x720 MBUI_MODCHECK=1 ./out/linux/mod/_build/native/release/build/kitdemo/kitdemo.exe > "$log" 2>&1 &
app=$!
cleanup() {
  kill "$app" 2>/dev/null || true
  wait "$app" 2>/dev/null || true
}
trap cleanup EXIT
exec 3< <(tail --pid="$app" -n +1 -f "$log")
await() {
  local line
  while IFS= read -r -t 30 line <&3; do
    printf '%s\n' "$line"
    [[ "$line" == *"$1"* ]] && return 0
  done
  printf 'modifier contract: no %s\n' "$1" >&2
  return 1
}
await 'MODCHECK ready'
window=$(timeout 15 xdotool search --onlyvisible --sync --name '^mbui modifier check$')
xdotool windowfocus --sync "$window"
xdotool mousemove --window "$window" 100 100
xdotool mousedown 1 keydown Alt_L
await 'MODCHECK held 4'
xdotool mouseup 1 keyup Alt_L
await 'MODCHECK release 4'
await 'MODCHECK held 0'
xdotool mousedown 1 keydown Shift_L
await 'MODCHECK held 1'
xdotool keyup Shift_L
await 'MODCHECK held 0'
xdotool mouseup 1
await 'MODCHECK release 0'
