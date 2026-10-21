#!/bin/bash
# effect.mb (src/effect): its own tests on native and JS, the window's runtime on the frames' clock (src/ui/fx_test.mbt),
# and the demo of a screen, its logic and a simulated backend on one clock over seeds (src/effectdemo). A seeded test
# that fails says its seed: SEED=<n> scripts/effect-test.sh replays it.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
code=0
for t in native js; do
  echo "== effect, $t"
  moon test --target $t -p mbui/effecttest 2>&1 | grep -v "$F" | tail -${LINES_OUT:-30}
  [ ${PIPESTATUS[0]} = 0 ] || code=1
done
echo "== the window's runtime and the demo, js"
moon test --target js src/ui/fx_test.mbt 2>&1 | grep -v "$F" | tail -${LINES_OUT:-30}
[ ${PIPESTATUS[0]} = 0 ] || code=1
moon test --target js -p mbui/effectdemo 2>&1 | grep -v "$F" | tail -${LINES_OUT:-30}
[ ${PIPESTATUS[0]} = 0 ] || code=1
exit $code
