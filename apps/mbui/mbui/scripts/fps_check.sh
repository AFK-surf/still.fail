#!/bin/bash
# The Tester's tests at other frame rates: by default a test's run_for goes straight to its end (no frames between);
# here they run again with frames drawn on its way while the app asks for them, as a host draws them (MBUI_TEST_FPS:
# frames a second), at 60, 120, 24 and 7, and must come out the same: what a test asserts at a moment is what is so
# at that moment, however many frames came before it. Only run_for's way has them: what the test walks itself (its
# inputs, `frame()`) is on the display's frames as ever.
# FPS="…" for other rates; PKGS="…" for other packages (the Tester's: mbui/view's own tests make their frames
# themselves, each at the moment it says).
# In CI on native as scripts/test_native.sh builds them (the same programs, their units kept); elsewhere on wasm-gc.
set -o pipefail
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
pkgs=${PKGS:-mbui/ui mbui/motion mbui/kit mbui/kitdemo/gallery mbui/effectdemo}
code=0
for fps in ${FPS:-60 120 24 7}; do
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    out=$(MBUI_TEST_FPS=$fps LINES_OUT=100000 bash "$D/test_native.sh" $pkgs 2>&1 | grep -av '^TDUMP')
  else
    args=()
    for p in $pkgs; do args+=(-p "$p"); done
    out=$(MBUI_TEST_FPS=$fps moon_tests "${args[@]}" 2>&1 | grep -av '^TDUMP')
  fi
  st=$?
  # (how what moves goes and each file's bars, said where the run says them (src/ui/tester_fps.mbt: motion_runs): kept
  # whole, out of what is shown)
  [ -z "${MOTION_OUT:-}" ] || echo "$out" | grep -a '^MOTION ' >> "$MOTION_OUT"
  out=$(echo "$out" | grep -av '^MOTION ')
  echo "$fps fps: $(echo "$out" | grep -a '^Total tests' | tail -1)"
  if [ $st != 0 ]; then
    echo "$out" | grep -a -E 'test .* failed|not built whole|takes no presses|Abort|exited with' | cut -c1-600 | head -40
    code=1
  fi
done
exit $code
