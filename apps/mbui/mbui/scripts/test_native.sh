#!/bin/bash
# The tests on native, on any system (a test's program links no host's code: its host is the Tester's fake,
# mbui/hostapi): the same tests as on JS (scripts/test.sh), each package's; what differs between the two backends
# shows here.
#   scripts/test_native.sh [PKG…]      by default ui, view, motion, kit, md, kitdemo's gallery (the hosts' kept runs),
#                                      effecttest, effectdemo
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
pkgs=${*:-mbui/ui mbui/view mbui/motion mbui/kit mbui/figure mbui/kitdemo/gallery mbui/effecttest mbui/effectdemo}
args=()
for p in $pkgs; do args+=(-p "$p"); done
# The kinds of test program a package has none of (internal: a test in its own files; blackbox: *_test.mbt;
# whitebox: *_wbtest.mbt), which moon builds anyway, each the whole of mbui, and never runs: scripts/mbc puts a
# stand-in in their place (MBC_EMPTY_TESTS, as apps/mbui/scripts/test.sh has it)
empty=""
for p in $pkgs; do
  d=src/${p#mbui/}; n=$(basename "$d"); [ -d "$d" ] || continue
  [ -n "$(ls "$d"/*.mbt 2>/dev/null | grep -vE '_(wb)?test\.mbt$' | xargs grep -l '^test ' 2>/dev/null)" ] || empty="$empty ${p#mbui/}/$n.internal_test"
  [ -n "$(ls "$d"/*_test.mbt 2>/dev/null | grep -v '_wbtest\.mbt$')" ] || empty="$empty ${p#mbui/}/$n.blackbox_test"
  [ -n "$(ls "$d"/*_wbtest.mbt 2>/dev/null)" ] || empty="$empty ${p#mbui/}/$n.whitebox_test"
done
export MBC_EMPTY_TESTS="$empty"
# The small packages' programs (motion's, kit's, the gallery's, effecttest's, effectdemo's: a few files of tests each,
# the whole of mbui in each) compiled without optimising (MBC_LIGHT_TESTS, as apps/mbui/scripts/test.sh has it): what
# they test is the code, not how fast it runs. A change to ui or view compiles their units again in each of them
# beside ui's and view's own: ~400 s of the 845 s of compile on CI's four cores, the native job past its 5 minutes,
# 2026-11-01 (#3221, run 41311978750)
light=""
for p in $pkgs; do
  case $p in mbui/ui | mbui/view) continue ;; esac
  n=$(basename "$p")
  light="$light ${p#mbui/}/$n.internal_test ${p#mbui/}/$n.blackbox_test ${p#mbui/}/$n.whitebox_test"
done
export MBC_LIGHT_TESTS="$light"
F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
moon_test_native "${args[@]}" 2>&1 | grep -v "$F" | tail -${LINES_OUT:-60}
r=${PIPESTATUS[0]}
exit $r
