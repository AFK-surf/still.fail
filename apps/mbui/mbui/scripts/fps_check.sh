#!/bin/bash
# The Tester's tests at other frame rates: by default a test's run_for goes straight to its end (no frames between);
# here they run again with the display's frames drawn on the way (MBUI_TEST_FPS: frames a second), at 60, 120, 24 and
# 7, and must come out the same: what a test asserts at a moment is what is so at that moment, however many frames came
# before it (docs/determinism.md). FPS="…" for other rates.
set -o pipefail
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
code=0
for fps in ${FPS:-60 120 24 7}; do
  out=$(MBUI_TEST_FPS=$fps moon test --target js -p mbui/ui -p mbui/motion -p mbui/kit -p mbui/md -p mbui/kitdemo -p mbui/effectdemo 2>&1 | grep -v '^TDUMP')
  st=$?
  echo "$fps fps: $(echo "$out" | grep -a '^Total tests' | tail -1)"
  if [ $st != 0 ]; then
    echo "$out" | grep -a -E '^\[mbui\] test .* failed' | cut -c1-300 | head -20
    code=1
  fi
done
exit $code
