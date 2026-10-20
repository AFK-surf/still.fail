#!/bin/bash
# One flow on the iOS simulator (e2e/run.sh ios): the app launched with the flow's script and the local still.fail's
# address (the simulator shares this Mac's network: its 127.0.0.1 is the Mac's, nothing to forward), its log followed
# (stderr, which simctl launch writes to a file: the host's log, the drive's lines), `DRIVE LOG do: …` acted on, until
# the app has ended (DRIVE PASS, or DRIVE FAIL and its shot) or its time is up. The app's shots and the core's data are
# the Mac's paths (MBUI_SHOT_DIR, MBUI_CORE_DATA: a simulator's app reads and writes them as they are), so the checks
# read them as on macOS. The screen recorded meanwhile (simctl io recordVideo).
#   e2e/ios-flow.sh NAME SCRIPT LOG       IOS_DEV the simulator's id, E2E_PKG the app's id, CORE and FILES
set -u
NAME=$1 SCRIPT=$2 LOG=$3
D="$(cd "$(dirname "$0")" && pwd)"
ROOT=$(cd "$D/.." && pwd)
OUT=$(dirname $LOG)/$NAME
PKG=${E2E_PKG:-fail.still.mbui.debug}
mkdir -p $OUT
. ${E2E_WORK:-$(cd $ROOT/.. && pwd)/e2e-local}/run/e2e-env.sh
# the app's environment (simctl hands SIMCTL_CHILD_<name> to it as <name>), a flow's `#env K=V` lines with it
export SIMCTL_CHILD_MBUI_CLOUD=$MBUI_CLOUD
export SIMCTL_CHILD_MBUI_CORE_ACCOUNT_B64=${E2E_ACCOUNT_B64:-$MBUI_CORE_ACCOUNT_B64}
export SIMCTL_CHILD_MBUI_CORE_DATA=$CORE
export SIMCTL_CHILD_MBUI_SHOT_DIR=$OUT
export SIMCTL_CHILD_MBUI_DRIVE_B64=$(base64 < $SCRIPT | tr -d '\n')
export SIMCTL_CHILD_MBUI_PICK_FILES="$FILES/e2e-photo.jpg|$FILES/e2e-data.bin"
export SIMCTL_CHILD_MBUI_CALL_LOG=1 SIMCTL_CHILD_MBUI_MOTION_LOG=1 SIMCTL_CHILD_MBUI_IME_LOG=1
while IFS= read -r kv; do [ -n "$kv" ] && export "SIMCTL_CHILD_$kv"; done < <(sed -n 's/^#env //p' $SCRIPT)
RAW=$LOG.raw
: > $RAW
: > $RAW.stdout
xcrun simctl terminate $IOS_DEV $PKG >/dev/null 2>&1
# (waits are on events, not times: mbui's scripts/logwait.py, kqueue's)
LW="$ROOT/mbui/scripts/logwait.py"
xcrun simctl io $IOS_DEV recordVideo --codec h264 --force $OUT/$NAME.mp4 >/dev/null 2>$OUT/record.log &
REC=$!
python3 "$LW" --log $OUT/record.log --line 'Recording started' --deadline 30 >/dev/null || echo "the screen's recording did not start" >> $LOG
# the app up as its log says ("ios: launched"), then its pid as `simctl launch` says it (which itself can sit on for
# minutes after the app is up on a loaded Mac, so its end is not waited for)
xcrun simctl launch --stdout=$RAW.stdout --stderr=$RAW $IOS_DEV $PKG >>$LOG 2>&1 &
pid=
if python3 "$LW" --log $RAW --line '^ios: launched' --deadline 120 >/dev/null; then
  pid=$(python3 "$LW" --log $LOG --line "^$PKG: [0-9]+" --deadline 120 | sed "s/^$PKG: //")
fi
[ -n "$pid" ] || echo "the app did not start" >> $LOG
if [ -n "$pid" ]; then
  # the log followed as it is written, what the drive asks for beside it done (`DRIVE LOG do: …`), until the app ends
  # (DRIVE PASS, or DRIVE FAIL and its shot) or the flow's time is up
  tail -n +1 -f $RAW | while IFS= read -r line; do
    case "$line" in
      "DRIVE LOG do: "*) "$ROOT/scripts/e2e-local.sh" ${line#DRIVE LOG do: } < /dev/null >> $LOG 2>&1 & ;;
    esac
  done &
  FOLLOW=$!
  python3 "$LW" --pid $pid --deadline ${E2E_FLOW_TIMEOUT:-300} >/dev/null 2>&1
  [ $? = 2 ] && echo "the flow's time is up" >> $LOG
  kill $FOLLOW 2>/dev/null
  # (pkill takes a regex: "+1" as it is matched no tail, and every flow left its tail behind, 235 on Mini1 by
  # 2026-10-20; [+] is the plus itself)
  pkill -f "tail -n [+]1 -f $RAW" 2>/dev/null
fi
# the app's log, and its stdout
cat $RAW >> $LOG
cat $RAW.stdout >> $LOG
rm -f $RAW $RAW.stdout
xcrun simctl terminate $IOS_DEV $PKG >/dev/null 2>&1
kill -INT $REC 2>/dev/null
wait $REC 2>/dev/null
grep -q "^DRIVE PASS" $LOG
