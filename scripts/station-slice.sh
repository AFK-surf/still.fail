#!/bin/sh
# The station's test files of one slice, I/N (scripts/check.sh's station-tests, CI's check-station): the longest files
# first, one to a slice in turn, then every other file in order, every N-th, from where those left off. Dealt only by
# place, the three longest (replica-heap-bounded, rules-fork, lock-world-2: 31, 13 and 16 s on Studio of a slice's 70)
# came to one slice, check-station (5) 215-223 s of its 5 minutes where the others were 71-137, 2026-11-13. A file
# named here and gone is skipped; one grown long is added.
# Run in station/.
s=${1:-0/1}
i=${s%/*} n=${s#*/}
long="test/replica-heap-bounded.test.ts test/lock-world-1.test.ts test/lock-world-2.test.ts test/lock-world-3.test.ts"
long="$long test/rules-fork.test.ts test/lock-fork-choice.test.ts test/lock-roster.test.ts test/lock-roster4.test.ts"
long="$long test/lock-moved-model.test.ts"
ls test/*.test.ts | awk -v i="$i" -v n="$n" -v long="$long" '
  BEGIN { k = split(long, l, " "); for (j = 1; j <= k; j++) if (l[j] != "") want[l[j]] = 1 }
  { all[NR] = $0; if ($0 in want) { at[$0] = h++ } }
  END {
    for (r = 1; r <= NR; r++) if (all[r] in at && at[all[r]] % n == i) print all[r]
    m = h
    for (r = 1; r <= NR; r++) if (!(all[r] in at)) { if (m % n == i) print all[r]; m++ }
  }'
