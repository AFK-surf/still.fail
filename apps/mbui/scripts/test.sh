#!/bin/bash
# This module's tests against mbui's fake host (no window): still.fail's design system, its pages (over the fixtures),
# the media screens' parts and the core client's, the screens (src/sfscreens, scripts/screens.sh), then the flows seen
# again over their runs' cores (src/sfreplay/steps.mbt). UPDATE=1 refreshes snapshots. TARGETS: the targets they run
# on (native by default, as the apps are built; CI's check-mbui: native on Linux, and on macOS on main). PARTS: which
# of the two (app: the design system, the pages, the screens, gallery and player; replay: the core and the flows seen
# again), both by default; check-mbui runs each on a runner of its own. mbui's own: its scripts/test.sh.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
code=0
for t in ${TARGETS:-native}; do
  echo "=== $t"
  # (native, on any system: a test's program links no host's code, its host the Tester's fake (mbui/hostapi). Built
  # --release as the apps are, its C split and compiled in parallel by mbui's scripts/mbc (moon's cc on PATH): on
  # macos-15 the tests ran in 15 s against debug's 144 s (2026-10-20). An object made of the same inputs (by content)
  # is kept: a build over the last one's objects (mbui-check.yml's native cache) compiles only the units whose
  # functions changed. clang where there is one, as on macOS (MBC_REAL_CC says otherwise). Without ThinLTO unless
  # MBC_LTO says (its link is 30-40 s a test; main's run has it on: mbui-check.yml).)
  mode="--target $t"
  # (mbui's scripts/env.sh native_tests: the C split by mbui's scripts/mbc, units kept by content in MBC_STORE)
  if [ $t = native ]; then native_tests "$A"; mode=$NATIVE; fi
  # (the parts' packages in one moon test, which runs a package's tests in one executable and the packages side by
  # side: the flows in packages of their own for it, src/sfreplay/flows/*/)
  pkgs=""
  if [[ " ${PARTS:-app replay} " = *" app "* ]]; then
    pkgs="-p stillfail/sf -p stillfail/sfapp -p stillfail/sfapp/settings -p stillfail/gallery -p stillfail/player"
    pkgs="$pkgs -p stillfail/sfscreens"
  fi
  if [[ " ${PARTS:-app replay} " = *" replay "* ]]; then
    pkgs="$pkgs -p stillfail/core -p stillfail/sfreplay"
    for g in src/sfreplay/flows/*/; do pkgs="$pkgs -p stillfail/sfreplay/flows/$(basename "$g")"; done
  fi
  moon test $mode $pkgs ${UPDATE:+--update} 2>&1 | grep -v "$F" | tail -${LINES_OUT:-60}
  [ ${PIPESTATUS[0]} = 0 ] || code=1
done
exit $code
