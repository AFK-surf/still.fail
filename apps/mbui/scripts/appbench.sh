#!/bin/bash
# still.fail's scenes measured offscreen (src/sfbench: mbui's film bench, mbui/src/film/bench.mbt): sffix's made-up
# chats in a Tester of this Mac's text and pictures, each scene's script (scripts/bench/<scene>.drive) on the display's
# frames at 120 a second, a frame drawn only where the app asks for one, as a host draws. For each frame drawn: what was
# built and laid out, its work, encoding and GPU time, what of it differs from the frame before and what goes to
# the GPU; per scene the medians and 95th centiles, a row of the table, kept in bench/app-history.jsonl with the commit.
# Times are reported and compared, never a test's condition. No window.
#   scripts/appbench.sh                 every scene        SCENES="idle fling" scripts/appbench.sh   those
#   LABEL="what changed" scripts/appbench.sh               FRAMES=1: each scene's frames, a line each, in out/bench/
#   REPEAT=3 (by default): each scene run so many times, the run with the lowest median work kept (the counts are the
#   same each run; the times drift with the machine). First the machine waited for to be quiet (mbui's
#   bench_quiet.sh, QUIET_MAX seconds at most, 300 by default; QUIET=0 not)
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
mkdir -p out/bench bench
# scene   fixture    window     platform pointing
table="idle chat-long 1280x800 0 mouse
fling chat-long 390x844 2 finger
backswipe chat 390x844 2 finger
newchat home 390x844 2 finger
switch home 351x805 2 finger
keyboard chat 390x844 2 finger
medium chat 690x840 2 finger
medium-idle chat 690x840 2 finger
hover chat 1280x800 0 mouse
card chat 1280x800 0 mouse
send-wide chat 1280x800 0 mouse
whole chat 690x840 2 finger
open home 351x805 2 finger"
built=$(APP=sfbench MODE=release bash scripts/mac.sh build 2>&1) || { echo "$built" | grep -E "Error|error" -A6 | head -60; echo "appbench: sfbench not built"; exit 1; }
[ "${QUIET:-1}" = 0 ] || QUIET_MAX=${QUIET_MAX:-300} bash mbui/scripts/bench_quiet.sh
exe=./_build/native/release/build/stillfail/sfbench/sfbench.exe
commit=${COMMIT:-$(git rev-parse --short HEAD 2>/dev/null)}
rows=()
lines=()
code=0
while read -r scene fixture win platform pointing; do
  [ -n "${SCENES:-}" ] && ! echo " $SCENES " | grep -q " $scene " && continue
  frames=""
  [ "${FRAMES:-0}" = 1 ] && frames="$PWD/out/bench/$scene.frames"
  best=""
  best_work=""
  for k in $(seq 1 "${REPEAT:-3}"); do
    # (whole: every frame built anew, keeping nothing: what a frame built whole costs, whatever it is built for)
    whole=0
    [ $scene = whole ] && whole=1
    out=$(env MBUI_BENCH_WHOLE=$whole MBUI_FIXTURE=$fixture MBUI_WIN=$win MBUI_FILM_PLATFORM=$platform MBUI_POINTING=$pointing \
      MBUI_BENCH_NAME=$scene MBUI_BENCH_DRIVE="$PWD/scripts/bench/$scene.drive" MBUI_BENCH_FRAMES="$frames" "$exe" 2>&1)
    st=$?
    if [ $st != 0 ]; then
      echo "$scene: the run did not pass ($st)"
      echo "$out" | grep -E "^DRIVE" | tail -5
      code=1
      best=$out
      break
    fi
    work=$(echo "$out" | grep '^APPBENCH ' | grep -o '"work_ms":{"med":[0-9.e+-]*' | sed 's/.*://')
    if [ -z "$best_work" ] || awk "BEGIN{exit !($work < $best_work)}"; then
      best=$out
      best_work=$work
    fi
  done
  rows+=("$(echo "$best" | grep '^APPROW ' | cut -c8-)")
  lines+=("$(echo "$best" | grep '^APPBENCH ' | cut -c10-)")
done <<< "$table"
echo "commit $commit ${LABEL:+($LABEL)}"
echo "| scene | frames drawn / display frames | work ms in all | work ms med / p95 | build | layout | paint | encode | GPU | nodes | laid anew | instances | redrawn area | upload KB |"
echo "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"
for r in "${rows[@]}"; do echo "$r"; done
{
  printf '{"time": %s, "commit": "%s", "label": "%s", "scenes": [' "$(date +%s)" "$commit" "${LABEL:-}"
  first=1
  for l in "${lines[@]}"; do [ -z "$l" ] && continue; [ $first = 1 ] || printf ', '; printf '%s' "$l"; first=0; done
  printf ']}\n'
} >> bench/app-history.jsonl
exit $code
