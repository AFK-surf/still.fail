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
parts=${*:-core-ts station rust locks locks-moved rigs cloud}
status=0
for part in $parts; do
  echo "· side: $part"
  case $part in
    # The mesh on the real addon and iroh-relay (side/mesh-real.test.ts), and on simulated networks made up at random
    # (side/mesh-explore.test.ts, SIM_EXPLORE of them); a new device approved face to face over two real endpoints
    # (side/lock-pair-iroh.test.ts).
    core-ts) (cd client/core-ts && pnpm side) || status=1 ;;
    # The station's of real processes and the file system as they take their time (station/side): a lock across
    # processes, logs followed by fs.watch.
    station) (cd station && pnpm test:side) || status=1 ;;
    # The native parts' tests of real processes' timing (#[ignore = "side: …"]): a handover with no gap on real ports,
    # restarts' backoff, a signal that leaves a grandchild be.
    rust) for crate in launcher runner; do (cd station/native/$crate && cargo test --locked -- --ignored) || status=1; done ;;
    # The locks end to end (apps/mbui/e2e/locks.ts): alice's and bob's devices, each still.fail's core in Node,
    # against a cloud, a relay and two stations of their own on this machine (scripts/e2e-local.sh locks-all), the
    # station and the cloud frozen and started anew between; directories and ports of its own, beside the app's e2e.
    locks) (cd apps/mbui && E2E_WORK=${RUNNER_TEMP:-/tmp}/side-locks E2E_STATION=/tmp/side-locks-$(id -u) E2E_PORT=28700 \
      E2E_RELAY=28709 bash scripts/e2e-local.sh locks-all) || status=1 ;;
    # A workspace's chain handed over to its people's own logs and what is done in it after (apps/mbui/e2e/locks-moved.ts:
    # an owner's two apps and web page, an admin, a member, two stations, the cloud frozen; scripts/e2e-local.sh
    # locks-moved-all), a run of its own on ports and directories of its own (28740 is a stray relay's on the CI Mac).
    locks-moved) (cd apps/mbui && E2E_WORK=${RUNNER_TEMP:-/tmp}/side-locks-moved E2E_STATION=/tmp/side-moved-$(id -u) E2E_PORT=28760 \
      E2E_RELAY=28769 bash scripts/e2e-local.sh locks-moved-all) || status=1 ;;
    # A rig end to end (apps/mbui/e2e/rigs.ts): a machine enrolled as alice's rig beside the test station, asked for by
    # a chat's agent, granted, used, taken back (scripts/e2e-local.sh rigs-all), on ports and directories of its own.
    rigs) (cd apps/mbui && E2E_WORK=${RUNNER_TEMP:-/tmp}/side-rigs E2E_STATION=/tmp/side-rigs-$(id -u) E2E_PORT=28720 \
      E2E_RELAY=28729 bash scripts/e2e-local.sh rigs-all) || status=1 ;;
    # A self-hosted cloud on workerd (cloud/side): built, signing people in through an SMTP relay and an OpenID provider of
    # the test's own, over real sockets with a CA of its own.
    cloud) (cd cloud && pnpm side) || status=1 ;;
    *) echo "no side part $part"; status=1 ;;
  esac
done
exit $status
