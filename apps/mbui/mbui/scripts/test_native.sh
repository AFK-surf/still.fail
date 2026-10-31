#!/bin/bash
# The tests on native, on any system (a test's program links no host's code: its host is the Tester's fake,
# mbui/hostapi): the same tests as on JS (scripts/test.sh), each package's; what differs between the two backends
# shows here.
#   scripts/test_native.sh [PKG…]      by default ui, view, motion, kit, md, kitdemo's gallery (the hosts' kept runs),
#                                      effecttest, effectdemo; then, by default, what is refused by stopping the
#                                      program, each in a process of its own (scripts/refused_scale.sh)
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
pkgs=${*:-mbui/ui mbui/view mbui/motion mbui/kit mbui/kitdemo/gallery mbui/effecttest mbui/effectdemo}
args=()
for p in $pkgs; do args+=(-p "$p"); done
F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
moon_test_native "${args[@]}" 2>&1 | grep -v "$F" | tail -${LINES_OUT:-60}
r=${PIPESTATUS[0]}
if [ $# -eq 0 ]; then
  bash "$D/refused_scale.sh" || { [ $r -eq 0 ] && r=1; }
fi
exit $r
