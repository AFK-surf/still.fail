#!/bin/bash
# The made-up screens as the core's JSON both apps draw a screen from (client/fixtures/screens/NAME.json): each of
# src/sfscreens' modes (or those named) opened in the Tester as sffix opens it, what it asked of the core kept
# (src/sfapp/screen_dump_wbtest.mbt), written as its file; then held to the core's shapes (core-ts's
# scripts/screens-fill.ts). A mode on a page Android's ScreensRefTest does not open is said and left out.
#   apps/mbui/scripts/screens-dump.sh [MODE…]
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
S=$(cd "$A/../../client/fixtures/screens" && pwd)
modes=${*:-$(sed -n 's/^test "\([^"]*\)" {.*/\1/p' src/sfscreens/screens_wbtest.mbt)}
mkdir -p $A/out
out=$(mktemp -d)
# (the screens not there before this run: written again on a run after it)
NEW=""
for m in $modes; do [ -f $S/$m.json ] || NEW="$NEW $m"; done
MBUI_SCREEN_DUMP=$(echo $modes | tr ' ' ',') moon test --target native src/sfapp/screen_dump_wbtest.mbt > $out/log 2>&1 \
  || { grep -a -A8 '^Error\|FAILED' $out/log | head -40; rm -rf $out; exit 1; }
written=""
while IFS= read -r line; do
  name=$(echo "$line" | cut -d' ' -f2)
  json=$(echo "$line" | cut -d' ' -f3-)
  # (a screen written already, its `shows` and moment set by hand, kept: FORCE=1 writes it again)
  if [ -f $S/$name.json ] && [ -z "${FORCE:-}" ] && ! echo " ${NEW:-} " | grep -q " $name "; then
    continue
  fi
  if [ "$json" = "-" ]; then
    echo "screens-dump: $name stands on a page Android's test does not open: left out"
    continue
  fi
  echo "$json" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify(JSON.parse(s),null,2)+"\n"))' > $S/$name.json
  written="$written $name"
done < <(grep -a '^SCREENDUMP ' $out/log)
rm -rf $out
# each held to the core's shapes on its own: what one gets wrong said, the others still done
fail=0
for n in $written; do
  (cd "$A/../../client/core-ts" && node scripts/screens-fill.ts $n > /dev/null 2> $A/out/fill-$n.log) \
    || { echo "screens-dump: $n: $(grep -a '^Error' $A/out/fill-$n.log | head -1)"; fail=1; }
  rm -f $A/out/fill-$n.log
done
echo "screens-dump: written$written"
exit $fail
