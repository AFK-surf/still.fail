#!/bin/bash
# Type-check every target of this module (and mbui with it); print errors only. First (alone with `reads`, as
# still.fail's scripts/check.sh runs it): the app (src/sfapp, but its tests) reads where it runs through mbui's @ui
# (@ui.now, wake_after, platform, system_dark, window_inset, env), never @host's own, so that under a Tester nothing
# it reads comes from the machine the test runs on.
D="$(cd "$(dirname "$0")" && pwd)"
# (find and grep, no git: it runs in copies without one; no file to look in, or grep's error, fails the check)
files=$(find "$D/../src/sfapp" -name '*.mbt' ! -name '*_test.mbt' ! -name '*_wbtest.mbt' 2>/dev/null)
[ -n "$files" ] || { echo "apps/mbui/scripts/check.sh: no files of src/sfapp to look in" >&2; exit 1; }
IFS='
'
reads=$(grep -nHE '@host\.(now|wake_after|platform|system_dark|window_inset|env)([^A-Za-z0-9_]|$)' $files)
st=$?
unset IFS
[ $st -le 1 ] || { echo "apps/mbui/scripts/check.sh: could not search src/sfapp for @host's reads" >&2; exit 1; }
if [ -n "$reads" ]; then
  echo "apps/mbui/src/sfapp reads its host directly (use @ui's: mbui src/ui/hostread.mbt):"
  echo "$reads"
  exit 1
fi
[ "${1:-}" = reads ] && exit 0
. "$D/env.sh"
cd "$A"
for t in ${TARGETS:-js native}; do
  echo "=== $t"
  moon check --target $t --output-json 2>&1 | python3 "$MBUI_DIR/scripts/errs.py"
done
