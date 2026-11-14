#!/bin/sh
# The station's test files of one slice, I/N (scripts/check.sh's station-tests, CI's check-station), dealt by what
# each costs a runner's cores: the long files at their seconds below, the longest first, then every other file at two
# (a slice of some 108 of them took 200 core-seconds on Studio), each onto the slice with the least so far (the lowest
# among equals). Dealt one long file to a slice by place, rules-fork (125 core-seconds, its model's draws on four
# workers) took 2 in its slice beside its share of the rest, check-station (2) 148-218 s where the others were 73-171,
# eight runs of 2026-11-14. Seconds are user and system time alone on Studio with four workers (LOCK_FORK_WORKERS=4,
# as CI's runners have), 2026-11-14. On CI those two model runners cost more than that beside a slice's other files:
# dealt at 125 and 46, check-station (0) with rules-fork was 145-187 s and (1) with lock-roster4 127-152, the others
# 79-137 (fork-pr-6238 43593595033, ci/film-macos-oldest 43593584773, feat/mbui-viz 43593193529), so they count 230
# and 90, what those runs make of them. A file named here and gone is skipped; one grown long is added.
# Run in station/.
s=${1:-0/1}
i=${s%/*} n=${s#*/}
long="test/rules-fork.test.ts:230 test/lock-roster4.test.ts:90 test/replica-heap-bounded.test.ts:27"
long="$long test/lock-moved-model.test.ts:26 test/lock-world-2.test.ts:16 test/lock-world-1.test.ts:13"
long="$long test/lock-world-3.test.ts:13 test/lock-fork-choice.test.ts:10 test/lock-roster.test.ts:6"
ls test/*.test.ts | awk -v i="$i" -v n="$n" -v long="$long" '
  function put(f, c,   g, b) { b = 0; for (g = 1; g < n; g++) if (load[g] < load[b]) b = g; load[b] += c; if (b == i) print f }
  BEGIN { k = split(long, l, " ") }
  { have[$0] = 1; all[NR] = $0 }
  END {
    for (j = 1; j <= k; j++) { split(l[j], q, ":"); want[q[1]] = 1; if (q[1] in have) put(q[1], q[2]) }
    for (r = 1; r <= NR; r++) if (!(all[r] in want)) put(all[r], 2)
  }'
