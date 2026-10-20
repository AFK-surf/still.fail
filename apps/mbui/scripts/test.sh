#!/bin/bash
# This module's tests against mbui's fake host (no window): still.fail's design system, its pages (over the fixtures),
# the media screens' parts and the core client's, then the flows seen again over their runs' cores
# (src/sfreplay/steps.mbt). UPDATE=1 refreshes snapshots. TARGETS: the targets they run on (js by default; CI's
# check-mbui: js native). mbui's own: its scripts/test.sh.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
code=0
for t in ${TARGETS:-js}; do
  echo "=== $t"
  moon test --target $t -p stillfail/sf -p stillfail/sfapp -p stillfail/gallery -p stillfail/player ${UPDATE:+--update} 2>&1 | grep -v "$F" | tail -${LINES_OUT:-60}
  [ ${PIPESTATUS[0]} = 0 ] || code=1
  moon test --target $t -p stillfail/core -p stillfail/sfreplay -p stillfail/sfreplay/flows 2>&1 | grep -v "$F" | tail -${LINES_OUT:-8}
  [ ${PIPESTATUS[0]} = 0 ] || code=1
done
exit $code
