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
# Measured again file by file (each alone, four side by side, Studio, 2026-11-14): every file of 5 s or more at
# its seconds, rules-fork and lock-roster4 kept at what CI makes of their models' workers. Dealt with the old list's
# nine long files and 2 for the rest, slice 3 held 322 measured seconds where the others held 215-288, and was
# check-station (3) 184-204 s on every push for hours (comma-stats 27 s, replica-retire 20, mb-reader-timeline 18,
# mb-replica 16, autoarchive-last-bounded 14, accounts-routes 12, counted 2 each); dealt by these, 241-259 and
# rules-fork's slice 297. A file grown long is added, one named here and gone skipped.
# Run in station/.
s=${1:-0/1}
i=${s%/*} n=${s#*/}
long="test/rules-fork.test.ts:230 test/lock-roster4.test.ts:90 test/replica-heap-bounded.test.ts:52"
long="$long test/memory-sync-random.test.ts:45 test/lock-moved-model.test.ts:42 test/replica-retire.test.ts:33"
long="$long test/cold-routes.test.ts:31 test/comma-stats.test.ts:27 test/lock-world-1.test.ts:23"
long="$long test/updates.test.ts:22 test/lock-world-3.test.ts:21 test/lock-world-2.test.ts:19"
long="$long test/mb-replica.test.ts:19 test/mb-reader-timeline.test.ts:18 test/comma-workspace-inflight.test.ts:13"
long="$long test/comma-stats-build-bounded.test.ts:11 test/hub.test.ts:11 test/lock-forks.test.ts:11"
long="$long test/mb-reader-usage-page.test.ts:11 test/lock-root-gone-ways.test.ts:10"
long="$long test/replica-stations.test.ts:10 test/store.test.ts:10 test/comma-router-once.test.ts:8"
long="$long test/legacy-decision-session-store.test.ts:8 test/updates-routes.test.ts:8"
long="$long test/accounts-routes.test.ts:7 test/cold-hub.test.ts:7 test/dirsync.test.ts:7"
long="$long test/legacy-said-write-bounded.test.ts:7 test/lock-root-out.test.ts:7 test/remote.test.ts:7"
long="$long test/rules-lock.test.ts:7 test/comma-adaptive-page.test.ts:6 test/comma-held-reconnect.test.ts:6"
long="$long test/hub-routes.test.ts:6 test/hub-tools.test.ts:6 test/logins.test.ts:6 test/mb-legacy.test.ts:6"
long="$long test/usage-compact-source.test.ts:6 test/card-answers-window.test.ts:5"
long="$long test/chat-list-home-interleaved.test.ts:5 test/chat-list-index-reader.test.ts:5"
long="$long test/lock-moved-pin.test.ts:5 test/mb-recent-chat.test.ts:5 test/subagent-hook.test.ts:5"
ls test/*.test.ts | awk -v i="$i" -v n="$n" -v long="$long" '
  function put(f, c,   g, b) { b = 0; for (g = 1; g < n; g++) if (load[g] < load[b]) b = g; load[b] += c; if (b == i) print f }
  BEGIN { k = split(long, l, " ") }
  { have[$0] = 1; all[NR] = $0 }
  END {
    for (j = 1; j <= k; j++) { split(l[j], q, ":"); want[q[1]] = 1; if (q[1] in have) put(q[1], q[2]) }
    for (r = 1; r <= NR; r++) if (!(all[r] in want)) put(all[r], 2)
  }'
