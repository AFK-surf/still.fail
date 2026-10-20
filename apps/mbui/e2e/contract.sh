#!/bin/bash
# The core's contract (e2e/contract.ts): every tape the Tester's flows are given again (e2e/traces/*.trace) put to a
# real core, this checkout's TS core in Node, against a local still.fail of its own (scripts/e2e-local.sh up: the dev
# cloud, a relay, a test station with ember's fake claude, the chat alice's other device made), and its answers
# compared with the tape's. A tape the core no longer answers so fails, saying how to record it again. Every tape starts
# from the same starting point (alice signed in: scripts/e2e-local.sh snapshot / restore), as each was recorded from
# one (e2e/run.sh's E2E_START), and does its own steps where it did them.
#
#   e2e/contract.sh [NAME…]     every tape, or those named; E2E_PORT, E2E_RELAY as e2e-local.sh's (its own by default,
#                               not the flows': 18887, 18840), E2E_KEEP=1 leaves the still.fail it started up
# Out: out/contract/ (each tape's core data, result.txt).
set -u
D="$(cd "$(dirname "$0")" && pwd)"
ROOT=$(cd "$D/.." && pwd)
export E2E_PORT=${E2E_PORT:-18887} E2E_RELAY=${E2E_RELAY:-18840}
export E2E_WORK=${E2E_WORK:-$ROOT/out/contract-local}
# (short: the station's runners listen on sockets in it)
export E2E_STATION=${E2E_STATION:-/tmp/mbc-$(id -u)}
OUT=$ROOT/out/contract
rm -rf "$OUT" && mkdir -p "$OUT"
L="$ROOT/scripts/e2e-local.sh"
START=contract
"$L" down >/dev/null 2>&1
"$L" up || exit 1
[ "${E2E_KEEP:-}" = 1 ] || trap '"$L" down >/dev/null' EXIT
. "$E2E_WORK/run/e2e-env.sh"
. "$ROOT/scripts/env.sh"
# the core run as alice's other device is: the station's natives, a HOME of its own; the core from the checkout
# e2e-local.sh installed
core() {
  (. "$E2E_WORK/run/station-env.sh"; export HOME=$E2E_WORK/contract-home; mkdir -p "$HOME"
   E2E_EMBER=$E2E_WORK/ember E2E_ORIGIN=$MBUI_CLOUD E2E_STATION=$E2E_STATION "$@")
}
# the starting point: alice signed in on a core of its own, then everything as it is now kept (snapshot)
core node "$D/contract.ts" --start "$OUT/start-core" || { echo "contract: no starting point"; exit 1; }
"$L" snapshot $START "$OUT/start-core" >/dev/null || exit 1
cat > "$OUT/seed.sh" <<SEED
#!/bin/bash
# for e2e/contract.ts: restore [TAG…] (back to the starting point, each tag's drive folder seeded) or step WORDS (a tape's step: scripts/e2e-local.sh WORDS)
set -e
export E2E_WORK=$E2E_WORK E2E_STATION=$E2E_STATION E2E_PORT=$E2E_PORT E2E_RELAY=$E2E_RELAY
case "\$1" in
  restore) "$L" restore $START >/dev/null
           for tag in "\${@:2}"; do "$L" drive-seed "\$tag" >/dev/null; done ;;
  step) "$L" \$2 >/dev/null ;;
  *) echo "seed: \$1?" >&2; exit 1 ;;
esac
SEED
chmod +x "$OUT/seed.sh"
core env E2E_CORE_DATA=$OUT/core E2E_START_CORE=$E2E_WORK/snapshots/$START/core E2E_SEED=$OUT/seed.sh \
  node "$D/contract.ts" "$@" | tee "$OUT/result.txt"
exit ${PIPESTATUS[0]}
