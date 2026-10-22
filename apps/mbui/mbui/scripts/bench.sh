#!/bin/bash
# mbui's hill-climb (src/bench, after nanoui's hillclimb/): five scenes built,
# laid out, painted and drawn by Metal into an offscreen texture, no window.
#   scripts/bench.sh [run]        release build, run, append to bench/history.jsonl
#   scripts/bench.sh build        only build
#   scripts/bench.sh nanoui       run nanoui's own hillclimb too (NANOUI: its clone,
#                                 ZIG: a Zig 0.17 binary), then compare
#   scripts/bench.sh compare      compare the last runs (bench/history.jsonl and
#                                 $NANOUI/hillclimb/history.jsonl)
# LABEL="what changed" names the run; SCENES=text,list FRAMES=600 MS=500 REPEAT=5.
# A scene runs frames filling about MS ms (300), at least 300; FRAMES fixes the
# count (nanoui's 300 when run beside nanoui).
# Each run first waits for the machine to be quiet (scripts/bench_quiet.sh;
# QUIET=0 skips that) and prints its load.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
EXE=_build/native/release/build/bench/bench.exe
build() {
  # as scripts/mac.sh builds (the C split: scripts/mbc; MBC_SPLIT=0 compiles it whole, to compare)
  PATH="$("$D/mbc" shim "$PWD/out/mbc/bin"):$PATH" \
    moon build --target native --release src/bench 2>&1 | python3 "$D/errs.py" >&2
  [ -x $EXE ]
}
quiet() {
  [ "${QUIET:-1}" = 0 ] || bash "$D/bench_quiet.sh"
}
run() {
  mkdir -p bench
  BENCH_LABEL="${LABEL:-}" BENCH_SCENES="${SCENES:-}" BENCH_FRAMES="${FRAMES:-}" BENCH_MS="${MS:-}" BENCH_REPEAT="${REPEAT:-}" \
    BENCH_HISTORY=bench/history.jsonl ./$EXE
}
nanoui() {
  [ -n "$NANOUI" ] || { echo "NANOUI: the path of a nanoui clone" >&2; exit 1; }
  (cd "$NANOUI/hillclimb" && ${ZIG:-zig} build run -- --label "${LABEL:-}" ${SCENES:+--scene $SCENES} ${ONLY:+--only $ONLY})
}
compare() {
  python3 "$D/bench_compare.py" bench/history.jsonl ${NANOUI:+"$NANOUI/hillclimb/history.jsonl"}
}
case "${1:-run}" in
  build) build ;;
  run) build && quiet && run && compare ;;
  nanoui) FRAMES="${FRAMES:-300}"; build && (cd "$NANOUI/hillclimb" && ${ZIG:-zig} build) && quiet && run && nanoui && compare ;;
  compare) compare ;;
esac
