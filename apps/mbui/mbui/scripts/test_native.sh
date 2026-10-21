#!/bin/bash
# The tests on native, on macOS (the hosts' Objective-C linked in: scripts/cc_apple.sh): the same tests as on JS
# (scripts/test.sh), each package's, against the fake host; what differs between the two backends shows here.
#   scripts/test_native.sh [PKG…]      by default ui, motion, kit, md, kitdemo, effecttest
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
pkgs=${*:-mbui/ui mbui/motion mbui/kit mbui/md mbui/kitdemo mbui/effecttest}
args=()
for p in $pkgs; do args+=(-p "$p"); done
F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
MOON_CC="$D/cc_apple.sh" moon test --target native "${args[@]}" 2>&1 | grep -v "$F" | tail -${LINES_OUT:-60}
exit ${PIPESTATUS[0]}
