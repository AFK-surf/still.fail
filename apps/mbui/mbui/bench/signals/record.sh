#!/bin/bash
# What still.fail's app does with mbui's signals, written down as it runs: a copy of apps/mbui with every call into the
# signals traced (record/trace.patch: a line a call, MBUI_SIGNALS_TRACE), its offscreen film (src/sffilm) run over the
# made-up chats through scripted flows (scripts/motion/*.drive) in a phone's window, a fold's and a desktop's, a trace a
# flow kept in traces/<flow>.trace.gz for replay.sh (a flow whose script does not pass is kept as far as it went: what
# the app did meanwhile is as real). A Mac (the film's renderer); no screen.
#   bench/signals/record.sh                 every flow below
#   FLOWS="lists-phone send-lines" bench/signals/record.sh
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
. "$D/../../scripts/env.sh"
APP=$(cd "$D/../../.." && pwd)
OUT=$D/out
C=$OUT/record-src
mkdir -p "$OUT/traces"
rsync -a --delete --exclude _build --exclude out --exclude node_modules --exclude .git "$APP/" "$C/"
(cd "$C/mbui" && patch -s -p1 < "$D/record/trace.patch")
# The film's Tester keeps nothing (every frame built whole, Tester::new): kept here as a host keeps it (parts kept,
# kept_part.mbt), so the traces are a host's frames. ROWS=1: a list's rows kept too (kept_rows.mbt; off on a host
# since #2175): what the app would do with them on, its traces in traces-rows/.
T=$C/mbui/src/ui/tester.mbt
sed -i '' 's/^  parts_on.val = false$/  parts_on.val = true/' "$T"
grep -q '^  parts_on.val = true$' "$T" || { echo "record.sh: Tester::new's parts_on not found"; exit 1; }
TR=$D/traces
if [ "${ROWS:-}" = 1 ]; then
  sed -i '' 's/^  rows_kept_on.val = false$/  rows_kept_on.val = true/' "$T"
  grep -q '^  rows_kept_on.val = true$' "$T" || { echo "record.sh: Tester::new's rows_kept_on not found"; exit 1; }
  TR=$D/traces-rows
fi
cd "$C"
APP=sffilm MODE=release bash scripts/mac.sh build > "$OUT/record-build.log" 2>&1 || { tail -40 "$OUT/record-build.log"; exit 1; }
EXE=$C/_build/native/release/build/stillfail/sffilm/sffilm.exe
# name | the flow's drive | fixture | window | platform (2: a phone's touch, 0: a desktop's mouse)
all="lists-phone|lists-phone|home|390x844|2
search-phone|search-phone|home|390x844|2
send-lines|send-lines|chat|390x844|2
send-long|send-long|chat|390x844|2
answer|answer|chat|390x844|2
conflict|conflict|chat|390x844|2
cards|cards|chat|390x844|2
tape|tape|chat|690x840|2
tape-stack|tape-stack|chat|690x840|2
tape-images|tape-images|chat|690x840|2
fold-composer|composer-focus-medium|chat|690x840|2
search-medium|search-medium|home|800x880|2
lists-medium|lists-wide|chat|760x900|0
lists-wide|lists-wide|chat|1280x800|0
send-lines-wide|send-lines-wide|chat|1280x800|0
search-wide|search-wide|chat|1280x800|0
wide-images|wide-images|chat|1280x800|0
files-browse|files-browse|drive|1280x800|0"
printf '%s\n' "$all" | while IFS='|' read -r name drive fixture win platform; do
  if [ -n "${FLOWS:-}" ] && ! printf ' %s ' "$FLOWS" | grep -q " $name "; then continue; fi
  rm -f "$OUT/traces/$name.trace"
  env MBUI_FIXTURE="$fixture" MBUI_WIN="$win" MBUI_FILM_PLATFORM="$platform" MBUI_FILM="$OUT/traces/$name.mp4" \
    MBUI_FILM_DRIVE="$C/scripts/motion/$drive.drive" MBUI_SIGNALS_TRACE="$OUT/traces/$name.trace" "$EXE" \
    > "$OUT/traces/$name.log" 2>&1 || echo "$name: the film failed (out/traces/$name.log)"
  printf '%-16s %6s frames %8s calls\n' "$name" "$(grep -c '^F$' "$OUT/traces/$name.trace" || true)" \
    "$(wc -l < "$OUT/traces/$name.trace" | tr -d ' ')"
  mkdir -p "$TR"
  gzip -9 -n -c "$OUT/traces/$name.trace" > "$TR/$name.trace.gz"
done
