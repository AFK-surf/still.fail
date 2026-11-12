#!/bin/sh
# What the suite's two runs said of each frame set side by side: the run keeping rows as a device does (MBUI_TEST_FRAMES
# 1) and the one keeping none (and MBUI_TEST_KEEP_NONE 1), their `KEPT` lines (ui's tester_rows_kept.mbt, gathered by
# KEPT_OUT). A line: KEPT <made> <moment> <nth at it> <judged> <raw> <asked>.
#   scripts/kept_compare.sh KEPT_A KEPT_B [LOG_B]      (KEPT_SAID_MOST=n: n lines of each list, the counts whole)
# Said, in this order: frames whose asking (what the app asked of its host and sent its core) differs, which come
# first, as what is drawn after them is not of one walk; frames drawn otherwise (judged: on a 1024th of a device
# pixel); frames the same so judged but not to the bit (raw: said, not judged); frames one run drew and the other did
# not, and the Testers whose frame counts differ; and (LOG_B) each test failed in the run keeping none, those that
# assert what is kept marked. Its exit: 1 where anything but raw differs.
set -u
a=$1; b=$2; log=${3:-}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# (the tests that assert what is kept: red in the run keeping none by what they assert, not by what is drawn; the ones
# the baseline round showed so, #5654)
kept_asserting='view_ride_wbtest|view_kept_wbtest'
# (a key said more than once, Testers made at one place in two processes run side by side (each counts its own), told
# apart by the how-manieth it is in its run's lines, which come in the same order in both)
keyed() { grep -a '^KEPT ' "$1" | awk '{ k = $2 "|" $3 "|" $4; c[k]++; print k "|" c[k], $5, $6, $7 }' | LC_ALL=C sort -k1,1; }
keyed "$a" > "$t/all_a"; keyed "$b" > "$t/all_b"
# (a key's `#n` is the how-manieth Tester made at its place in its process: a test failed in one run makes fewer there
# after it (a loop of cases cut short), every later Tester of that place numbered otherwise, so two Testers' frames
# would be set side by side. A place whose Testers are otherwise many in the two runs is said, its frames not compared;
# every other place's numbers are the same Testers', their counters their own)
places() { cut -d'|' -f1 "$1" | LC_ALL=C sort -u | sed 's/#[0-9]*$//' | LC_ALL=C sort | uniq -c | awk '{ print $2, $1 }'; }
places "$t/all_a" > "$t/pa"; places "$t/all_b" > "$t/pb"
LC_ALL=C join -a1 -a2 -e0 -o 0,1.2,2.2 "$t/pa" "$t/pb" | awk '$2 != $3' > "$t/cut"
uncut() { awk 'NR == FNR { cut[$1] = 1; next } { p = $1; sub(/\|.*/, "", p); sub(/#[0-9]+$/, "", p); if (!(p in cut)) print }' "$t/cut" "$1"; }
uncut "$t/all_a" > "$t/a"; uncut "$t/all_b" > "$t/b"
LC_ALL=C join "$t/a" "$t/b" > "$t/j"
awk '$4 != $7' "$t/j" > "$t/io"
awk '$4 == $7 && $2 != $5' "$t/j" > "$t/px"
awk '$4 == $7 && $2 == $5 && $3 != $6' "$t/j" > "$t/raw"
cut -d' ' -f1 "$t/a" > "$t/ka"; cut -d' ' -f1 "$t/b" > "$t/kb"
LC_ALL=C comm -23 "$t/ka" "$t/kb" > "$t/only_a"; LC_ALL=C comm -13 "$t/ka" "$t/kb" > "$t/only_b"
per() { cut -d'|' -f1 "$1" | LC_ALL=C sort | uniq -c | awk '{ print $2, $1 }'; }
per "$t/ka" > "$t/na"; per "$t/kb" > "$t/nb"
LC_ALL=C join -a1 -a2 -e0 -o 0,1.2,2.2 "$t/na" "$t/nb" | awk '$2 != $3' > "$t/counts"
n() { wc -l < "$1" | tr -d ' '; }
# (each list whole; KEPT_SAID_MOST lines of each where it is said for people, a job's summary)
most() { if [ -n "${KEPT_SAID_MOST:-}" ]; then head -"$KEPT_SAID_MOST"; else cat; fi; }
echo "frames: $(n "$t/all_a") kept, $(n "$t/all_b") none, $(n "$t/j") in both and compared"
echo "places whose Testers are otherwise many (kept, none), their frames not compared: $(n "$t/cut")"; sed 's/^/  /' "$t/cut" | most
echo "asked otherwise: $(n "$t/io")"; sed 's/|/ /g' "$t/io" | awk '{ print "  " $1, $2, $3 }' | most
echo "drawn otherwise: $(n "$t/px")"; sed 's/|/ /g' "$t/px" | awk '{ print "  " $1, $2, $3 }' | most
echo "the same drawn, not to the bit (not judged): $(n "$t/raw")"
echo "drawn in the run keeping rows alone: $(n "$t/only_a")"; sed 's/^/  /' "$t/only_a" | most
echo "drawn in the run keeping none alone: $(n "$t/only_b")"; sed 's/^/  /' "$t/only_b" | most
echo "Testers drawing otherwise many frames (kept, none): $(n "$t/counts")"; sed 's/^/  /' "$t/counts" | most
bad=$(( $(n "$t/io") + $(n "$t/px") + $(n "$t/only_a") + $(n "$t/only_b") + $(n "$t/cut") ))
if [ -n "$log" ]; then
  grep -a '\] test .* failed' "$log" | LC_ALL=C sort -u > "$t/failed"
  echo "failed keeping none: $(n "$t/failed") ($(grep -Ec "$kept_asserting" "$t/failed") of them asserting what is kept)"
  # (each with its words, whole: a check's own (the line @halt.saying printed above where it said them, `  at …`), or
  # what the failure's line says itself (an assertion's FAILED:), and the lines under it)
  awk -v k="$kept_asserting" '
    /^\[[^]]*\] test .* failed/ {
      print "  " ($0 ~ k ? "(asserts what is kept) " : "") $0
      if (said != "" && $0 !~ /FAILED:/) print "      said: " said
      on = 1; said = ""; next
    }
    on && /^  / { print "    " $0; next }
    /^  at [^ ]+:[0-9]/ && prev != "" && prev !~ /^(KEPT|MOTION|CLOCKREAD) / { said = prev }
    { on = 0; prev = $0 }' "$log"
  bad=$(( bad + $(grep -Evc "$kept_asserting" "$t/failed") ))
fi
[ $bad = 0 ]
