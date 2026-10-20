#!/bin/bash
# The core's contract (e2e/contract.ts): every tape the Tester's flows are given again (e2e/traces/*.trace) put to a
# real core, this checkout's TS core in Node, against a local still.fail of its own (scripts/e2e-local.sh up: the dev
# cloud, a relay, a test station with ember's fake claude, the chat alice's other device made), and its answers
# compared with the tape's. A tape the core no longer answers so fails, saying how to record it again. The tapes of
# each run they were recorded in (contract.ts --runs) get a still.fail of their own, fresh, as that run had.
#
#   e2e/contract.sh [NAME…]     every tape, or those named; E2E_PORT, E2E_RELAY as e2e-local.sh's (its own by default,
#                               not the flows': 18887, 18840), E2E_KEEP=1 leaves the last still.fail it started up
# Out: out/contract/ (the cores' data, result.txt).
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
. "$ROOT/scripts/env.sh"
# what the drive's tapes' run had put there before them (the flows that are not tapes: 18-drive-upload's two files)
FILES=$OUT/files
mkdir -p "$FILES"
cp "$MBUI_DIR/test/images/$(ls "$MBUI_DIR/test/images" | grep -i '\.jpg$' | head -1)" "$FILES/e2e-photo.jpg"
head -c 9437184 /dev/zero > "$FILES/e2e-data.bin"
cat > "$OUT/seed.sh" <<SEED
#!/bin/bash
# a tape's world (e2e/contract.ts world()): drive TAG [FILE…], drive-big TAG, or peer ARGS (alice's other device)
set -e
export E2E_WORK=$E2E_WORK E2E_STATION=$E2E_STATION E2E_PORT=$E2E_PORT E2E_RELAY=$E2E_RELAY
case "\$1" in
  drive) "$L" drive-seed "\$2" >/dev/null
         for f in "\${@:3}"; do cp "$FILES/\$f" "$E2E_STATION/home/e2e-\$2/\$f"; done ;;
  drive-big) "$L" drive-big "\$2" >/dev/null ;;
  peer) "$L" "\$@" >/dev/null ;;
  *) echo "seed: \$1?" >&2; exit 1 ;;
esac
SEED
chmod +x "$OUT/seed.sh"
# (no core needed to list them)
runs=$(E2E_EMBER=$EMBER node "$D/contract.ts" --runs "$@") || exit 1
fails=0
while IFS= read -r tapes; do
  "$L" down >/dev/null 2>&1
  "$L" up || exit 1
  . "$E2E_WORK/run/e2e-env.sh"
  # (as alice's other device is run: the station's natives, a HOME of its own; the core from the checkout
  # e2e-local.sh installed)
  (. "$E2E_WORK/run/station-env.sh"; export HOME=$E2E_WORK/contract-home; mkdir -p "$HOME"
   E2E_EMBER=$E2E_WORK/ember E2E_ORIGIN=$MBUI_CLOUD E2E_CORE_DATA=$OUT/core E2E_STATION=$E2E_STATION \
     E2E_SEED=$OUT/seed.sh node "$D/contract.ts" $tapes) | tee -a "$OUT/result.txt"
  [ "${PIPESTATUS[0]}" = 0 ] || fails=$((fails + 1))
done <<< "$runs"
[ "${E2E_KEEP:-}" = 1 ] || "$L" down >/dev/null
exit $((fails > 0))
