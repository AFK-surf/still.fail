#!/bin/bash
# What a flow's `log do: WORDS` asks of the runner (e2e/run.sh, e2e/android-flow.sh): scripts/e2e-local.sh WORDS done
# beside the run, then said done to the app (mbui's drive `done N-WORD`, src/host/done_watch.h): a file of the run's
# directory for it, N-WORD (the N-th `do:` of the run and its first word: 1-freeze, 2-peer), written as .N-WORD then
# renamed, its words `ok` (`ok WORDS`: what it found, said on a `SAY WORDS` line) or what went wrong. The app is told of it by its host as it comes; nothing waits on a time.
#   e2e/runner-do.sh N DIR WORDS…     DIR the run's directory on this machine (macOS: MBUI_DONE_DIR)
#   ADB="adb -s …" PKG=… e2e/runner-do.sh N android WORDS…    the app's own files/done on the emulator
set -u
D="$(cd "$(dirname "$0")" && pwd)"
ROOT=$(cd "$D/.." && pwd)
N=$1 DIR=$2
shift 2
NAME=$N-$1
# (what it found, where it says so on a line of its own, `SAY WORDS`: told to the app with the ok, for its drive's
# `typedone N-WORD` to type, as a code another device shows)
out=$(mktemp)
if "$ROOT/scripts/e2e-local.sh" "$@" < /dev/null | tee "$out"; [ "${PIPESTATUS[0]}" = 0 ]; then
  said=ok
  found=$(grep '^SAY ' "$out" | tail -1 | cut -c5-)
  [ -z "$found" ] || said="ok $found"
else
  said="scripts/e2e-local.sh $* failed"
fi
rm -f "$out"
echo "RUNNER done $NAME: $said"
if [ "$DIR" = android ]; then
  q=${said//\'/\'\\\'\'}
  $ADB shell "run-as $PKG sh -c \"mkdir -p files/done && printf '%s\\n' '$q' > files/done/.$NAME && mv files/done/.$NAME files/done/$NAME\"" < /dev/null
else
  mkdir -p "$DIR"
  printf '%s\n' "$said" > "$DIR/.$NAME" && mv "$DIR/.$NAME" "$DIR/$NAME"
fi
