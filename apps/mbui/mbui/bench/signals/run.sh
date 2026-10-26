#!/bin/bash
# mbui's signals against JavaScript's signal engines on this machine: js-reactivity-benchmark (pinned below) as it is,
# and its suites ported case for case to MoonBit (src/native) on mbui's signals compiled natively, as still.fail's apps
# are built (scripts/mbc's split C). Results in out/.
#   bench/signals/run.sh                      every engine (about 10 minutes on an M4)
#   ENGINES=alien,preact,vue bench/signals/run.sh   those of the benchmark's
#   REPEATS=5                                 samples a case, the fastest kept
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
. "$D/../../scripts/env.sh"
cd "$D"
JRB=https://github.com/transitive-bullshit/js-reactivity-benchmark.git
JRB_COMMIT=2c273f164cea0d7eae9d383f4b9ab699e550109d
R=${REPEATS:-5}
OUT=$D/out
J=$OUT/jrb
mkdir -p "$OUT"
[ -d "$J/.git" ] || git clone -q "$JRB" "$J"
git -C "$J" checkout -q -f "$JRB_COMMIT"
(
  unset MOON_CC
  export MBC_REAL_CC=${MBC_REAL_CC:-$(command -v clang || command -v cc)} MBC_LTO=0 MBC_STORE=$D/_build/mbc-store
  PATH="$("$D/../../scripts/mbc" shim "$D/_build/mbc-bin"):$PATH"
  moon build --target native --release src/native
)
EXE=$(find _build/native/release/build -name native.exe | head -1)
"$EXE" self
(cd "$J" && pnpm install --frozen-lockfile > /dev/null && pnpm build > /dev/null)
: > "$OUT/native.jsonl"
for s in kairo mol s dynamic cellx; do "$EXE" $s "$R" >> "$OUT/native.jsonl"; done
"$EXE" mem 1 > "$OUT/mem.json"
(cd "$J" && node --expose-gc dist/index.js --repeats "$R" --timeout 600000 ${ENGINES:+--framework "$ENGINES"} \
  --output "$OUT/js" > /dev/null 2> "$OUT/js.log") || { tail -20 "$OUT/js.log"; exit 1; }
node merge.mjs "$OUT/js.json" "$OUT/report" "mbui signals (native)=$OUT/native.jsonl" > /dev/null
cat "$OUT/mem.json"
sed -n '1,/^## Every case/p' "$OUT/report.md"
