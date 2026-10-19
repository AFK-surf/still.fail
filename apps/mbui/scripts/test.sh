#!/bin/bash
# This module's tests against mbui's fake host (no window): still.fail's design system, its pages (over the fixtures),
# the media screens' parts and the core client's. UPDATE=1 refreshes snapshots. mbui's own: its scripts/test.sh.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
moon test --target js -p stillfail/sf -p stillfail/sfapp -p stillfail/gallery -p stillfail/player ${UPDATE:+--update} 2>&1 | grep -v "$F" | tail -${LINES_OUT:-60}
code=${PIPESTATUS[0]}
moon test --target js -p stillfail/core 2>&1 | grep -v "$F" | tail -8
[ ${PIPESTATUS[0]} = 0 ] || code=1
exit $code
