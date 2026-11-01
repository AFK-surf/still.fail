#!/bin/bash
# UI tests against the fake host (no window), the motion package, the components (kit), the Markdown parser;
# mbui/text's (UAX #29, #14 and #9 against Unicode's own test files); then mbui's text against the
# platform's own drawing on macOS and in a browser (scripts/textdiff.sh mac web: fails on a string that differs and
# did not before; TEXTDIFF=0 skips it). UPDATE=1 refreshes snapshots.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
moon_test_native -p mbui/ui -p mbui/motion -p mbui/kit -p mbui/figure -p mbui/dmath -p mbui/zip ${UPDATE:+--update} 2>&1 | grep -v "$F" | tail -${LINES_OUT:-60}
code=${PIPESTATUS[0]}
moon_test_native -p mbui/text 2>&1 | grep -v "$F" | tail -8
[ ${PIPESTATUS[0]} = 0 ] || code=1
if [ "${TEXTDIFF:-1}" != 0 ]; then
  bash "$D/textdiff.sh" mac web 2>&1 | grep -v '^  '
  [ ${PIPESTATUS[0]} = 0 ] || code=1
fi
exit $code
