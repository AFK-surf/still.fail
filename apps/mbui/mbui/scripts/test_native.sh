#!/bin/bash
# The tests on native, on any system (a test's program links no host's code: its host is the Tester's fake,
# mbui/hostapi): the same tests as on JS (scripts/test.sh), each package's; what differs between the two backends
# shows here. Not kitdemo's: an app's main, its tests' program links its host (its tapes are replayed on JS).
#   scripts/test_native.sh [PKG…]      by default ui, motion, kit, md, effecttest
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
pkgs=${*:-mbui/ui mbui/motion mbui/kit mbui/md mbui/effecttest}
args=()
for p in $pkgs; do args+=(-p "$p"); done
F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
moon test --target native "${args[@]}" 2>&1 | grep -v "$F" | tail -${LINES_OUT:-60}
exit ${PIPESTATUS[0]}
