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
PKG=${E2E_PKG:-fail.still.android.dev}
mkdir -p $OUT
. ${E2E_WORK:-$(cd $ROOT/.. && pwd)/e2e-local}/run/e2e-env.sh
DIR=/data/data/$PKG/files/e2e
ENVS="MBUI_DONE_DIR=/data/data/$PKG/files/done;MBUI_CLOUD=$MBUI_CLOUD;MBUI_CORE_ACCOUNT_B64=${E2E_ACCOUNT_B64:-$MBUI_CORE_ACCOUNT_B64};MBUI_DRIVE_B64=$(base64 < $SCRIPT | tr -d '\n');MBUI_PICK_FILES=$DIR/e2e-photo.jpg|$DIR/e2e-data.bin;MBUI_IME_LOG=1;MBUI_CALL_LOG=1;MBUI_MOTION_LOG=1;MBUI_LOCALE=zh-CN"
# a flow's `#env K=V` lines, for this run
EXTRA=$(grep '^#env ' $SCRIPT | sed 's/^#env //' | tr '\n' ';')
[ -n "$EXTRA" ] && ENVS="$ENVS;${EXTRA%;}"
$ADB shell am force-stop $PKG
# (an earlier run's word of what it did, not this one's)
$ADB shell "run-as $PKG rm -rf files/done" 2>/dev/null
$ADB logcat -c
# The recording in the shell user's own directory (/data/local/tmp: there once the system runs; /sdcard is only once
# the emulated storage is mounted, which a first flow on an emulator just booted may come before), begun before the
# app: screenrecord says when it has its display. Its failure the flow's: no recording, no evidence.
VIDEO=/data/local/tmp/e2e-$NAME.mp4
$ADB shell "screenrecord --verbose --time-limit 180 $VIDEO" > $OUT/screenrecord.log 2>&1 &
REC=$!
started=$(node "$ROOT/scripts/waitfor.mjs" --deadline 20 --what "screenrecord recording" --log $OUT/screenrecord.log \
  --line 'Configuring recorder|Main display is|ERROR|Unable|rror') || started="its first words never came (screenrecord.log)"
case "$started" in
  Configuring*|*"Main display is"*) ;;
  *) echo "the screen not recorded: $started" >> $LOG; kill $REC 2>/dev/null; wait $REC 2>/dev/null; exit 1 ;;
esac
# a flow's `#android-intent ARGS`: the intent it starts with (another app's share: -a …SEND --eu …STREAM content://…)
INTENT=$(sed -n 's/^#android-intent //p' $SCRIPT | head -1)
$ADB shell am start -n $PKG/dev.mbui.MainActivity $INTENT --es env "'$ENVS'" >/dev/null
result=1
deadline=$(($(date +%s) + ${E2E_FLOW_TIMEOUT:-300}))
# the log, line by line as logcat writes it (a FIFO read with the deadline's time left: no waiting for a time), until
# the run ends, the app is gone (ActivityManager's word of its process dying) or the time is up
FIFO=$LOG.fifo
rm -f $FIFO && mkfifo $FIFO
$ADB logcat -v raw -s mbui:I StillFailCore:I AndroidRuntime:E DEBUG:I libc:F > $FIFO 2>/dev/null &
LCAT=$!
# (two processes of their own, not a pipeline: each one's pid known, both ended at the end; a pipeline's first part
# would outlive a kill of its last, and `wait` on it never return)
AMF=$LOG.am.fifo
rm -f $AMF && mkfifo $AMF
$ADB logcat -v raw -s ActivityManager:I > $AMF 2>/dev/null &
AM=$!
grep --line-buffered "Process $PKG (pid [0-9]*) has died" < $AMF > $FIFO &
GONE=$!
exec 3< $FIFO
done_=0
dos=0
while [ $done_ = 0 ]; do
  left=$((deadline - $(date +%s)))
  [ $left -gt 0 ] || { echo "the flow's time is up (${E2E_FLOW_TIMEOUT:-300} s)" >> $LOG; break; }
  IFS= read -r -t $left line <&3
  rc=$?
  # (a read past the time left: the deadline, seen above; the FIFO's writers gone: the logcats ended)
  [ $rc = 0 ] || [ -n "$line" ] || { [ $rc -gt 128 ] && continue; echo "the log ended" >> $LOG; break; }
  echo "$line" >> $LOG
  case "$line" in
    "SHOT "*) n_=${line#SHOT }; $ADB exec-out screencap -p < /dev/null > $OUT/$n_.png ;;
    # (done beside the run, then said done to the app: the n-th do's file, e2e/runner-do.sh)
    "DRIVE LOG do: "*) dos=$((dos + 1))
      ADB="$ADB" PKG=$PKG "$D/runner-do.sh" $dos android ${line#DRIVE LOG do: } >> $LOG 2>&1 & ;;
    "DRIVE PASS"*) result=0; done_=1 ;;
    "DRIVE FAIL on screen"*) $ADB exec-out screencap -p < /dev/null > $OUT/fail.png; done_=1 ;;
    *"Process $PKG (pid "*") has died"*) echo "the app is gone" >> $LOG; done_=1 ;;
  esac
done
exec 3<&-
kill $LCAT $AM $GONE 2>/dev/null
wait $LCAT $AM $GONE 2>/dev/null
rm -f $FIFO $AMF
# (screenrecord ended by its interrupt writes the file out and exits, and the adb shell with it)
$ADB shell pkill -INT screenrecord >/dev/null 2>&1
wait $REC 2>/dev/null
$ADB pull $VIDEO $OUT/$NAME.mp4 >/dev/null 2>&1
$ADB shell rm -f $VIDEO
exit $result
