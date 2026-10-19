#!/bin/bash
# One flow on the emulator (e2e/run.sh android): the app started with the flow's script and the local still.fail's
# address (adb reverse brings the emulator's 127.0.0.1 ports to this machine's), its log followed: `SHOT name` taken
# with adb's screencap, `DRIVE LOG do: …` acted on, until DRIVE PASS or DRIVE FAIL. The screen recorded meanwhile.
#   e2e/android-flow.sh NAME SCRIPT LOG
set -u
NAME=$1 SCRIPT=$2 LOG=$3
D="$(cd "$(dirname "$0")" && pwd)"
ROOT=$(cd "$D/.." && pwd)
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
ADB="$SDK/platform-tools/adb -s emulator-${EMU_PORT:-5580}"
OUT=$(dirname $LOG)/$NAME
PKG=${E2E_PKG:-dev.mbui.demo}
mkdir -p $OUT
. ${E2E_WORK:-$(cd $ROOT/.. && pwd)/e2e-local}/run/e2e-env.sh
DIR=/data/data/$PKG/files/e2e
ENVS="MBUI_CLOUD=$MBUI_CLOUD;MBUI_CORE_ACCOUNT_B64=${E2E_ACCOUNT_B64:-$MBUI_CORE_ACCOUNT_B64};MBUI_DRIVE_B64=$(base64 < $SCRIPT | tr -d '\n');MBUI_PICK_FILES=$DIR/e2e-photo.jpg|$DIR/e2e-data.bin;MBUI_IME_LOG=1;MBUI_CALL_LOG=1;MBUI_MOTION_LOG=1"
# a flow's `#env K=V` lines, for this run
EXTRA=$(grep '^#env ' $SCRIPT | sed 's/^#env //' | tr '\n' ';')
[ -n "$EXTRA" ] && ENVS="$ENVS;${EXTRA%;}"
$ADB shell am force-stop $PKG
$ADB logcat -c
$ADB shell "screenrecord --time-limit 180 /sdcard/e2e-$NAME.mp4" >/dev/null 2>&1 &
REC=$!
sleep 1
$ADB shell am start -n $PKG/dev.mbui.MainActivity --es env "'$ENVS'" >/dev/null
result=1
deadline=$(($(date +%s) + ${E2E_FLOW_TIMEOUT:-300}))
# the log, line by line (into a file, read as it grows: macOS's bash has no way to end a process substitution), until
# the run ends or its time is up; the logcat ended after
CAT=$LOG.cat
$ADB logcat -v raw -s mbui:I StillFailCore:I AndroidRuntime:E DEBUG:I libc:F > $CAT 2>/dev/null &
LCAT=$!
seen=0
done_=0
while [ $done_ = 0 ] && [ $(date +%s) -lt $deadline ]; do
  sleep 0.3
  n=$(wc -l < $CAT | tr -d ' ')
  if [ "$n" -le "$seen" ]; then
    # quiet: still there? (asked now and then, twice before giving up)
    idle=$((${idle:-0} + 1))
    # (by what pidof prints: adb's exit code does not say)
    alive() { [ -n "$($ADB shell pidof $PKG </dev/null 2>/dev/null | tr -d '\r\n ')" ]; }
    if [ $((idle % 20)) = 0 ] && ! alive; then
      sleep 3
      alive || { sleep 3; alive || { echo "the app is gone" >> $LOG; break; }; }
    fi
    continue
  fi
  while IFS= read -r line; do
    echo "$line" >> $LOG
    case "$line" in
      "SHOT "*) n_=${line#SHOT }; $ADB exec-out screencap -p < /dev/null > $OUT/$n_.png ;;
      "DRIVE LOG do: "*) "$ROOT/scripts/e2e-local.sh" ${line#DRIVE LOG do: } < /dev/null >> $LOG 2>&1 & ;;
      "DRIVE PASS"*) result=0; done_=1 ;;
      "DRIVE FAIL on screen"*) sleep 1; $ADB exec-out screencap -p < /dev/null > $OUT/fail.png; done_=1 ;;
    esac
  done < <(sed -n "$((seen + 1)),${n}p" $CAT)
  seen=$n
done
kill $LCAT 2>/dev/null
wait $LCAT 2>/dev/null
rm -f $CAT
sleep 2
$ADB shell pkill -INT screenrecord >/dev/null 2>&1
wait $REC 2>/dev/null
sleep 1
$ADB pull /sdcard/e2e-$NAME.mp4 $OUT/$NAME.mp4 >/dev/null 2>&1
$ADB shell rm -f /sdcard/e2e-$NAME.mp4
exit $result
