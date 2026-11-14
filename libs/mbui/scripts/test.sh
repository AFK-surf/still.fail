#!/bin/bash
# UI tests against the fake host (no window), the motion package, the components (kit; headless: the headless ones),
# the Markdown parser;
# mbui/text's (UAX #29, #14 and #9 against Unicode's own test files); then mbui's text against the
# platform's own drawing on macOS and in a browser (scripts/textdiff.sh mac web: fails on a string that differs and
# did not before; TEXTDIFF=0 skips it). UPDATE=1 refreshes snapshots.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
# (the whole suite is CI's, a PR's: on Studio or a laptop it is half an hour of wasm-gc in a row where CI's native runs
# it in five minutes; outside CI run the test files a change touches, `moon test --target wasm-gc --release FILE`
# (the user, 2026-11-08). MBUI_WHOLE_SUITE=1 only when a person asked for the whole of it here.)
if [ -z "${GITHUB_ACTIONS:-}" ] && [ "${MBUI_WHOLE_SUITE:-}" != 1 ]; then
  echo "test.sh: the whole suite runs in the PR's CI, not here. Run the test files your change touches:" >&2
  echo "  moon test --target wasm-gc --release src/ui/<file>_test.mbt" >&2
  exit 2
fi
cd "$D/.."
F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
moon_tests -p mbui/ui -p mbui/motion -p mbui/kit -p mbui/headless -p mbui/figure -p mbui/dmath -p mbui/zip ${UPDATE:+--update} 2>&1 | grep -v "$F" | tail -${LINES_OUT:-60}
code=${PIPESTATUS[0]}
moon_tests -p mbui/text 2>&1 | grep -v "$F" | tail -8
[ ${PIPESTATUS[0]} = 0 ] || code=1
if [ "${TEXTDIFF:-1}" != 0 ]; then
  bash "$D/textdiff.sh" mac web 2>&1 | grep -v '^  '
  [ ${PIPESTATUS[0]} = 0 ] || code=1
fi
exit $code
