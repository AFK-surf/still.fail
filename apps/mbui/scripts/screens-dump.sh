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
# not yet drawn by Android's test: the reader (the text's bytes, which a screen's JSON does not answer with) and the
# security page (its state followed off the main thread there: "addObserver must be called on the main thread"); a
# chat flashing a message gone to (the going there is no page a screen's JSON opens)
skip=" reader reader-bars reader-contents reader-layout reader-md settings-security chat-flash chat-flash-mine "
modes=$(for m in $modes; do echo "$skip" | grep -q " $m " || echo $m; done)
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
# every screen there embedded in src/sfscreens' tests (its moon.pkg's pre-build, between its `screens:` lines) and
# listed (screens_list_wbtest.mbt: android_ref_wbtest.mbt's screens)
P=src/sfscreens/moon.pkg
L=src/sfscreens/screens_list_wbtest.mbt
names=$(cd $S && ls *.json | sed 's/\.json$//' | grep -v -x allowed | LC_ALL=C sort)
{
  sed -n '1,/\/\/ screens: begin/p' $P
  for n in $names; do
    v=screen_$(echo $n | tr '-' '_')
    printf '    {\n      "input": "../../../../client/fixtures/screens/%s.json",\n      "output": "%s_wbtest.mbt",\n      "command": ":embed -i $input -o $output --name %s",\n    },\n' $n $v $v
  done
  sed -n '/\/\/ screens: end/,$p' $P
} > $P.new && mv $P.new $P
{
  echo '// written by scripts/screens-dump.sh: every screen of client/fixtures/screens, its JSON embedded (moon.pkg)'
  echo
  echo '///|'
  echo '/// The screens (their names, as client/fixtures/screens has them, and their JSON).'
  echo 'fn screens_kept() -> Array[(String, String)] {'
  echo '  ['
  for n in $names; do echo "    (\"$n\", screen_$(echo $n | tr '-' '_')),"; done
  echo '  ]'
  echo '}'
} > $L
exit $fail
