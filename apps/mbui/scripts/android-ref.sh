#!/bin/bash
# The mbui app held to still.fail's Android app, screen by screen, on one emulator (CI's mbui-android-ref job): each
# screen of client/fixtures/screens is the core's JSON both apps draw it from (Android's ScreensRefTest, sffix's
# MBUI_FIXTURE=json: src/sfapp/fixture_json.mbt). Android's pictures are the references, kept in the repository
# (client/fixtures/screens/android/, with android.json: the emulator's system they were taken on); the mbui app's are
# drawn on each run and compared with them pixel by pixel (scripts/android_ref.py), the regions allowed.json lets
# differ left out. The system's bars are in demo mode for both (the same clock, battery and signal).
#
#   scripts/android-ref.sh refs [NAME…]      Android's pictures taken anew (its app and test APKs installed: ANDROID_APK,
#                                            ANDROID_TEST_APK), into client/fixtures/screens/android/ with android.json
#   scripts/android-ref.sh mbui [NAME…]      the mbui app's (APP=sffix's debug APK installed: MBUI_APK) into
#                                            out/android-ref/mbui/, on the references' system (else it fails, saying so)
#   scripts/android-ref.sh compare [NAME…]   each against its reference: out/android-ref/<name>.png (Android | mbui |
#                                            the pixels that differ), out/android-ref/report.md; fails on a difference
#                                            allowed.json does not allow
#   scripts/android-ref.sh ci                CI's: refs (REFS=1, or none kept yet: then held to those kept), mbui, compare
#
# ADB (the emulator's: adb -s emulator-$EMU_PORT, 5554 by default). NAMEs: client/fixtures/screens/*.json by default.
set -u
D="$(cd "$(dirname "$0")" && pwd)"
A=$(cd "$D/.." && pwd)
ROOT=$(cd "$A/../.." && pwd)
S=$ROOT/client/fixtures/screens
R=$S/android
O=$A/out/android-ref
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
ADB=${ADB:-$SDK/platform-tools/adb -s emulator-${EMU_PORT:-5554}}
PKG=${MBUI_PKG:-fail.still.mbui.debug}
M=fail.still.android.motion
die() { echo "android-ref: $*" >&2; exit 1; }
cmd=${1:-}; shift || true
names=${*:-$(cd $S && ls *.json | sed 's/\.json$//' | grep -v -x allowed)}

# The system's bars the same for both apps: demo mode, 12:00, a full battery, full Wi-Fi, no notifications.
demo() {
  # the system's own window motions off (an app's start, a window's), the apps' own left as they are: a picture is of
  # the app's window, not of the system's way to it
  $ADB shell settings put global window_animation_scale 0
  $ADB shell settings put global transition_animation_scale 0
  $ADB shell settings put global sysui_demo_allowed 1
  $ADB shell settings put global sysui_tuner_demo_on 1
  for c in "enter" "clock -e hhmm 1200" "battery -e level 100 -e plugged false" "network -e wifi show -e level 4 -e mobile hide" \
    "notifications -e visible false"; do
    $ADB shell am broadcast -a com.android.systemui.demo -e command $c | grep -q 'Broadcast completed' || die "demo mode: $c not taken"
  done
}

# The emulator's system, as the references record it: what a run of the mbui app is held to.
machine() {
  printf '{"fingerprint": "%s", "sdk": "%s", "size": "%s", "density": "%s"}\n' \
    "$($ADB shell getprop ro.build.fingerprint | tr -d '\r')" "$($ADB shell getprop ro.build.version.sdk | tr -d '\r')" \
    "$($ADB shell wm size | sed 's/.*: //' | tr -d '\r')" "$($ADB shell wm density | sed 's/.*: //' | tr -d '\r')"
}

case "$cmd" in
  refs)
    [ -n "${ANDROID_APK:-}" ] && { $ADB install -r -t "$ANDROID_APK" > /dev/null || die "Android's app not installed"; }
    [ -n "${ANDROID_TEST_APK:-}" ] && { $ADB install -r -t "$ANDROID_TEST_APK" > /dev/null || die "Android's tests not installed"; }
    demo
    $ADB shell rm -rf /sdcard/Android/data/$M/files/screens
    filter=""
    # (a screen's test is its name in camel case: chat-cards → ScreensRefTest#chatCards)
    for n in $names; do
      t=$(python3 -c 'import sys; w=sys.argv[1].split("-"); print(w[0]+"".join(x[:1].upper()+x[1:] for x in w[1:]))' "$n")
      filter="${filter:+$filter,}fail.still.android.motion.ScreensRefTest#$t"
    done
    mkdir -p $O && $ADB shell am instrument -w -e class "$filter" $M.test/androidx.test.runner.AndroidJUnitRunner > $O/instrument.log 2>&1
    if ! grep -q '^OK (' $O/instrument.log; then
      grep -a -E 'FAILURES|Exception|at fail\.still|Error' $O/instrument.log | head -20
      # (what it drew, to see why: out/android-ref/failed/)
      mkdir -p $O/failed && $ADB pull /sdcard/Android/data/$M/files/screens/. $O/failed > /dev/null 2>&1
      $ADB logcat -d -s StillFailCore:* AndroidRuntime:E System.err:W 2>/dev/null | tail -80 > $O/failed/logcat.txt
      die "Android's screens not drawn ($O/instrument.log)"
    fi
    mkdir -p $R
    for n in $names; do
      $ADB pull /sdcard/Android/data/$M/files/screens/$n.png $R/$n.png > $O/pull.log 2>&1 \
        || { cat $O/pull.log; $ADB shell ls -la /sdcard/Android/data/$M/files/screens/; die "$n: no picture"; }
    done
    # the system's bars, where the app's window lies under them (the test's word: each screen's alike)
    bars=$($ADB shell cat /sdcard/Android/data/$M/files/screens/$(echo $names | cut -d' ' -f1).bars | tr -d '\r')
    machine | python3 -c 'import json,sys; m=json.load(sys.stdin); t,b=sys.argv[1].split(); m["bars"]={"top":int(t),"bottom":int(b)}; print(json.dumps(m))' "$bars" > $R/android.json
    echo "android-ref: Android's pictures of $(echo $names | wc -w | tr -d ' ') screens in $R, taken on $(cat $R/android.json)"
    ;;
  mbui)
    [ -f $R/android.json ] || die "no references ($R/android.json): scripts/android-ref.sh refs first"
    have=$(machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["fingerprint"])')
    want=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["fingerprint"])' $R/android.json)
    [ "$have" = "$want" ] || die "the emulator's system is not the references': this one is $have, they were taken on $want (make them again: the refs job)"
    [ -n "${MBUI_APK:-}" ] && { $ADB install -r "$MBUI_APK" > /dev/null || die "the mbui app not installed"; }
    demo
    rm -rf $O/mbui && mkdir -p $O/mbui
    fail=0
    for n in $names; do
      json=$(python3 -c 'import json,sys,base64; print(base64.b64encode(json.dumps(json.load(open(sys.argv[1])),ensure_ascii=False,separators=(",",":")).encode()).decode())' $S/$n.json)
      # the moment pictured: the one the screen names (`at`) on the app's own clock (mbui's MBView shot_at: its frames
      # 1/60 s apart from 0, the clock still while the app awaits its host, an image decoding), told once that frame
      # is on the screen in the app's window ("SHOT n t"): adb's screencap takes it
      at=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("at", 3000))' $S/$n.json)
      log=$O/mbui/$n.log
      $ADB shell am force-stop $PKG
      $ADB logcat -c
      FIFO=$O/mbui/$n.fifo; rm -f $FIFO && mkfifo $FIFO
      $ADB logcat -v raw -s mbui:I AndroidRuntime:E > $FIFO 2>/dev/null &
      LCAT=$!
      exec 3< $FIFO
      $ADB shell am start -n $PKG/dev.mbui.MainActivity --ei shot_at $at --es env "'MBUI_FIXTURE=json;MBUI_FIXTURE_JSON_B64=$json'" > /dev/null
      ok=0
      # (the run ends at its shot, or the app's death is logged; the app says its way there every 30 frames, "shot:
      # frame n at t": 120 s with no word from it is a failure, however long the way takes on a machine drawing slowly)
      while :; do
        IFS= read -r -t 120 line <&3 || { echo "the log ended, or 120 s with no word from the app" >> $log; break; }
        echo "$line" >> $log
        case "$line" in
          "SHOT "*) $ADB exec-out screencap -p < /dev/null > $O/mbui/$n.png; ok=1; break ;;
          *"FATAL EXCEPTION"*) break ;;
        esac
      done
      exec 3<&-
      # (what had the screen then, when no picture came)
      [ $ok = 1 ] || $ADB exec-out screencap -p < /dev/null > $O/mbui/$n.failed.png
      [ $ok = 1 ] || $ADB shell dumpsys window | grep -E 'mCurrentFocus|mFocusedApp' >> $log
      [ $ok = 1 ] || $ADB logcat -d -b crash,main,system | grep -E 'JNI DETECTED|Abort message|    in call|    from |FATAL|#0[0-9] pc' | head -40 >> $log
      kill $LCAT 2>/dev/null; wait $LCAT 2>/dev/null; rm -f $FIFO
      $ADB shell am force-stop $PKG
      if [ $ok = 1 ] && [ -s $O/mbui/$n.png ]; then echo "$n: drawn"; else echo "$n: not drawn ($log)"; tail -5 $log; fail=1; fi
    done
    exit $fail
    ;;
  compare)
    python3 "$D/android_ref.py" "$R" "$O/mbui" "$O" "$S/allowed.json" $names
    ;;
  ci)
    # CI's run (mbui-android-ref.yml): the runner's CPU said (the emulator draws in software on it); Android's
    # pictures taken anew where its app or the screens changed (REFS=1), held to those kept (a change is a new
    # reference: this run's, committed in its PR); then the mbui app's, compared
    fail=0
    echo "android-ref: on $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')"
    if [ "${REFS:-}" = 1 ] || [ ! -f $R/android.json ]; then
      rm -rf $O/kept && mkdir -p $O && { [ -f $R/android.json ] && cp -r $R $O/kept; true; }
      bash "$0" refs || exit 1
      # the same pictures again (a reference that differs from itself is no reference: the run says where)
      rm -rf $O/again && cp -r $R $O/again
      bash "$0" refs > /dev/null || exit 1
      python3 "$D/android_ref.py" "$O/again" "$R" "$O/again-diff" /nonexistent $names | grep '^| [a-z]' \
        | sed 's/^/android-ref: Android twice: /'
      python3 "$D/android_ref.py" "$O/again" "$R" "$O/again-diff" /nonexistent $names > /dev/null || fail=1
      # held to those kept as android_ref.py compares (a channel a step apart the same: the same picture has come out so
      # on another runner, at circles' edges), the kept ones then left as they are
      if [ -f $O/kept/android.json ] && cmp -s $O/kept/android.json $R/android.json \
        && python3 "$D/android_ref.py" "$O/kept" "$R" "$O/kept-diff" /nonexistent $names > /dev/null; then
        (cd $ROOT && git checkout -- client/fixtures/screens/android)
      else
        echo "android-ref: Android's pictures are not the ones kept: commit this run's (its artifact's client/fixtures/screens/android) in the PR"
        [ -f $O/kept/android.json ] && python3 "$D/android_ref.py" "$O/kept" "$R" "$O/kept-diff" /nonexistent $names | grep '^| [a-z]'
        fail=1
      fi
    fi
    bash "$0" mbui || exit 1
    rm -rf $O/mbui-again && cp -r $O/mbui $O/mbui-again && cp $R/android.json $O/mbui-again/
    bash "$0" mbui > /dev/null || exit 1
    python3 "$D/android_ref.py" "$O/mbui-again" "$O/mbui" "$O/mbui-again-diff" /nonexistent $names | grep '^| [a-z]' \
      | sed 's/^/android-ref: the mbui app twice: /'
    python3 "$D/android_ref.py" "$O/mbui-again" "$O/mbui" "$O/mbui-again-diff" /nonexistent $names > /dev/null || fail=1
    bash "$0" compare || fail=1
    exit $fail
    ;;
  *) die "refs, mbui or compare (scripts/android-ref.sh)" ;;
esac
