#!/bin/bash
# tape.sh : a dev build's tape of a run (the debug build keeps one each start: android/apk.json's
# MBUI_DRAW_LOG=1 MBUI_TEXT_RECORD=1 MBUI_LOG_FILE=tape-{start}.log, the 5 latest in the app's files/) taken off a
# device and seen again in a Tester on the same commit (mbui docs/determinism.md: a bug is a tape and a frame number).
#   scripts/tape.sh list [SERIAL]                       the tapes on the device, newest last
#   scripts/tape.sh pull [SERIAL] [NAME] [OUT]          one taken back (the newest by default) to OUT (out/tapes/NAME)
#   scripts/tape.sh replay LOG MODE [FRAME]             given again in a Tester over the fixture MODE (the run's
#                                                       MBUI_FIXTURE; src/sffix), up to FRAME if said: every frame's
#                                                       hash the run's, or the first that is not said
# A tape is of the app as it ran: replay it on the commit the build was made from (the build's number, its SHA).
set -u
D="$(cd "$(dirname "$0")" && pwd)"; M=$(cd "$D/.." && pwd)
ADB=${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}; P=${APP_ID:-fail.still.android.dev}
case "${1:-}" in
  list)
    "$ADB" ${2:+-s $2} shell run-as $P ls -l files/ | grep ' tape-' ;;
  pull)
    S=${2:-}; N=${3:-$("$ADB" ${S:+-s $S} shell run-as $P ls files/ | tr -d '\r' | grep '^tape-' | sort | tail -1)}
    [ -n "$N" ] || { echo "tape: no tape on the device (a dev build: android/apk.json's debug)" >&2; exit 1; }
    O=${4:-$M/out/tapes/$N}; mkdir -p "$(dirname "$O")"
    "$ADB" ${S:+-s $S} exec-out run-as $P cat "files/$N" > "$O" || exit 1
    echo "$O: $(wc -l < "$O") lines, $(grep -c 'DRAWHASH ' "$O") frames, $(grep -c 'INPUT ' "$O") inputs" ;;
  replay)
    LOG=$2; MODE=$3; FRAME=${4:-}
    NAME=$(basename "$LOG" .log | tr -c 'a-z0-9\n' '_' | tr '[:upper:]' '[:lower:]')
    (cd "$M" && python3 scripts/tape.py "$LOG" "$NAME" "$MODE" $FRAME) || exit 1
    T="$M/src/sfapp/tape_${NAME}_wbtest.mbt"
    . "$D/env.sh"; cd "$M"
    moon test --target wasm-gc --release -p stillfail/sfapp --filter "tape ${NAME}:*" 2>&1 | grep -v '^Warning\|^ *│\|^ *╭\|^ *╰\|^─' | tail -20
    rc=${PIPESTATUS[0]}; rm -f "$T"; exit $rc ;;
  *) sed -n 2,12p "$0"; exit 2 ;;
esac
