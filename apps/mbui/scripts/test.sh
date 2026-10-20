#!/bin/bash
# This module's tests against mbui's fake host (no window): still.fail's design system, its pages (over the fixtures),
# the media screens' parts and the core client's, the screens as the Mac draws them (src/sfscreens, scripts/screens.sh:
# on js), then the flows seen again over their runs' cores
# (src/sfreplay/steps.mbt). UPDATE=1 refreshes snapshots. TARGETS: the targets they run on (js by default; CI's
# check-mbui: js; check-mbui-native: native). PARTS: which of the two (app: the design system, the pages, gallery and
# player; replay: the core and the flows seen again), both by default; check-mbui runs each on a runner of its
# own. mbui's own: its scripts/test.sh.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
code=0
for t in ${TARGETS:-js}; do
  echo "=== $t"
  # (native on macOS: the hosts' Objective-C linked in by mbui's own wrapper, as a test's binary is given no
  # cc-link-flags: mbui's scripts/cc_apple.sh)
  if [ $t = native ] && [ "$(uname)" = Darwin ]; then export MOON_CC="$MBUI_DIR/scripts/cc_apple.sh"; else unset MOON_CC; fi
  # (the parts' packages in one moon test, which runs a package's tests in one executable and the packages side by
  # side: the flows in packages of their own for it, src/sfreplay/flows/*/)
  pkgs=""
  if [[ " ${PARTS:-app replay} " = *" app "* ]]; then
    pkgs="-p stillfail/sf -p stillfail/sfapp -p stillfail/gallery -p stillfail/player"
    [ $t = js ] && pkgs="$pkgs -p stillfail/sfscreens"
  fi
  if [[ " ${PARTS:-app replay} " = *" replay "* ]]; then
    pkgs="$pkgs -p stillfail/core -p stillfail/sfreplay"
    for g in src/sfreplay/flows/*/; do pkgs="$pkgs -p stillfail/sfreplay/flows/$(basename "$g")"; done
  fi
  moon test --target $t $pkgs ${UPDATE:+--update} 2>&1 | grep -v "$F" | tail -${LINES_OUT:-60}
  [ ${PIPESTATUS[0]} = 0 ] || code=1
done
exit $code
