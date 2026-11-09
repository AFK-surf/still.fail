#!/bin/bash
# Exercise the actual native preview window, its preparation, and its error path.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
if [ "${1:-}" != inside ]; then
  on_screen bash "$0" inside
  exit
fi
mkdir -p out
work=$(mktemp -d "$PWD/out/media-preview-test.XXXXXXXX")
pid=''
cleanup() {
  if [ -n "$pid" ]; then
    # Only children of the wrapper started below, not another task's app.
    for child in $(ps -axo pid=,ppid= | awk -v parent="$pid" '$2 == parent {print $1}'); do kill "$child" 2>/dev/null || true; done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT
printf 'until 整理发布清单\nexit\n' > "$work/prepare"
printf 'until 整理发布清单\nexit\n' > "$work/drive"
: > "$work/log"
# The outer invocation already holds the screen; the wrapper should not take it a second time.
env STILLFAIL_JOB_SCREEN= MBUI_FIXTURE=home MBUI_WIN=320x560 \
  bash scripts/media.sh preview "$work/drive" "$work/prepare" > "$work/log" 2>&1 &
pid=$!
"$MBUI_DIR/scripts/chk" logwait --log "$work/log" --line '^DRIVE PASS$' --pid "$pid" \
  --fail-log "$work/log" --fail-line '^DRIVE FAIL' --deadline 60
kill -0 "$pid"
children=$(ps -axo pid=,ppid= | awk -v parent="$pid" '$2 == parent {print $1}')
[ -n "$children" ] || { echo 'media-preview-test: no preview process after the drive' >&2; exit 1; }
for child in $children; do kill "$child"; done
wait "$pid" 2>/dev/null || true
pid=''
printf 'no-such-step\nexit\n' > "$work/bad"
if env STILLFAIL_JOB_SCREEN= MBUI_FIXTURE=home MBUI_WIN=320x560 \
    bash scripts/media.sh preview "$work/bad" > "$work/bad.log" 2>&1; then
  echo 'media-preview-test: a failed drive succeeded' >&2
  exit 1
fi
rg -q '^DRIVE FAIL' "$work/bad.log"
echo 'media-preview-test: preparation, interactive window and failed drive passed'
