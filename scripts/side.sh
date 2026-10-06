#!/bin/sh
# The side run (docs/development.md, "Tests"): the tests CI does not run because they are not the same every run (real
# time, real processes and sockets, networks made up at random), run every few hours, blocking nothing. A failure here
# is for an agent to reproduce as a test CI runs, one that fails the same way every time, and to fix; one it cannot
# reproduce is let be.
#
#   sh scripts/side.sh           every part's
#   sh scripts/side.sh core-ts   one part's
set -u
cd "$(dirname "$0")/.."
parts=${*:-core-ts station rust}
status=0
for part in $parts; do
  echo "· side: $part"
  case $part in
    # The mesh on the real addon and iroh-relay (side/mesh-real.test.ts), and on simulated networks made up at random
    # (side/mesh-explore.test.ts, SIM_EXPLORE of them).
    core-ts) (cd client/core-ts && pnpm side) || status=1 ;;
    # The station's of real processes and the file system as they take their time (station/side): a lock across
    # processes, logs followed by fs.watch.
    station) (cd station && pnpm test:side) || status=1 ;;
    # The native parts' tests of real processes' timing (#[ignore = "side: …"]): a handover with no gap on real ports,
    # restarts' backoff, a signal that leaves a grandchild be.
    rust) for crate in launcher runner; do (cd station/native/$crate && cargo test --locked -- --ignored) || status=1; done ;;
    *) echo "no side part $part"; status=1 ;;
  esac
done
exit $status
