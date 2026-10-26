#!/bin/bash
# The app's own use of the signals as the benchmark: every trace in traces/ (record.sh's) done again on mbui's signals
# as they are now, built as still.fail's apps are (scripts/mbc's split C), each checked (every computed ran as often as
# in the app) and timed; a row a trace and a table of what a frame does on average. Any machine with moon and clang.
#   bench/signals/replay.sh [REPEATS=5]
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
. "$D/../../scripts/env.sh"
cd "$D"
mkdir -p out/replay
for f in traces/*.trace.gz; do gzip -dc "$f" > "out/replay/$(basename "$f" .gz)"; done
(
  unset MOON_CC
  export MBC_REAL_CC=${MBC_REAL_CC:-$(command -v clang || command -v cc)} MBC_LTO=0 MBC_STORE=$D/_build/mbc-store
  PATH="$("$D/../../scripts/mbc" shim "$D/_build/mbc-bin"):$PATH"
  moon build --target native --release src/replay > /dev/null
)
EXE=$(find _build/native/release/build -name replay.exe | head -1)
"$EXE" out/replay/*.trace --repeats "${REPEATS:-5}"
