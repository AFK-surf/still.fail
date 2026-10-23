#!/bin/bash
# The mbui app held to still.fail's Android app, screen by screen, on one emulator (CI's mbui-android-ref job): each
# screen of client/fixtures/screens is the core's JSON both apps draw it from (Android's ScreensRefTest, sffix's
# MBUI_FIXTURE=json: src/sfapp/fixture_json.mbt). Android's pictures are the references, kept in the repository
# (client/fixtures/screens/android/, with android.json: the emulator's system they were taken on); the mbui app's are
# not taken of the app running: each screen is drawn in a Tester over the Android host's text (src/sfscreens/
# android_ref_wbtest.mbt), its draw list drawn offscreen by mbui-render on the same emulator, and compared with
# Android's pixel by pixel (scripts/android_ref.py), the regions allowed.json lets differ left out.
#
#   scripts/android-ref.sh refs [NAME…]      Android's pictures taken anew (its app and test APKs installed: ANDROID_APK,
#                                            ANDROID_TEST_APK), into client/fixtures/screens/android/ with android.json
#   scripts/android-ref.sh text [NAME…]      the Android host's text for each (screens/text-android.textrec): the mbui
#                                            app (APP=sffix's debug APK: MBUI_APK) run once to the screen's moment; for a
#                                            screen whose text the Tester lacks
#   scripts/android-ref.sh lists [NAME…]     the Tester's draw lists (out/android-ref/dl/), each with its picture's key
#   scripts/android-ref.sh need [NAME…]      the screens whose pictures are not kept for their keys (PICS)
#   scripts/android-ref.sh mbui [NAME…]      the mbui app's pictures into out/android-ref/mbui/: kept ones as they are,
#                                            the others' draw lists drawn by mbui-render (RENDER_APK: scripts/
#                                            render_android.sh's app) on the references' system (else it fails, saying
#                                            so) and kept
#   scripts/android-ref.sh compare [NAME…]   each against its reference: out/android-ref/<name>.png (Android | mbui |
#                                            the pixels that differ), out/android-ref/report.md; fails on a difference
#                                            allowed.json does not allow
#   scripts/android-ref.sh plan              the screens whose Android pictures CI's run would take (none: no Android
#                                            app to build)
#   scripts/android-ref.sh ci                CI's: refs (REFS=1, or none kept yet: then held to those kept), text (TEXT=1),
#                                            lists, mbui, compare; with no emulator where neither is asked for and every
#                                            picture is kept
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
MBUI_DIR=${MBUI_DIR:-$A/mbui}
# (moon_test_native: the screens' draw lists printed by a native test)
. "$MBUI_DIR/scripts/env.sh"
PKG=${MBUI_PKG:-fail.still.mbui.debug}
M=fail.still.android.motion
die() { echo "android-ref: $*" >&2; exit 1; }
# the mbui pictures kept by their keys (lists): the Actions cache's in CI
PICS=${PICS:-$A/out/android-ref-pics}
# What draws a draw list into the pictures compared, by its files' contents: mbui's renderer and what it reads of the
# draw list, its Android host and text, how its app is built, and this script and android_ref.py (how the window is put
# on the screen); the sources alone (an app build puts its .so beside them). Another of these, every screen drawn anew.
render_code() {
  (cd $ROOT && find apps/mbui/mbui/src/render apps/mbui/mbui/src/host/android_host.c apps/mbui/mbui/src/host/corner* \
    apps/mbui/mbui/src/ui/drawlist.mbt apps/mbui/mbui/src/ui/scene.mbt apps/mbui/mbui/src/ui/line.mbt \
    apps/mbui/mbui/src/ui/smooth.mbt apps/mbui/mbui/android/app/src/main/java apps/mbui/mbui/android/app/src/main/res \
    apps/mbui/mbui/android/app/src/main/AndroidManifest.xml apps/mbui/mbui/android/apk.json \
    apps/mbui/mbui/android/apk.lock apps/mbui/mbui/tools/apk/main.mbt apps/mbui/mbui/scripts/android.sh \
    apps/mbui/mbui/scripts/render_android_hook.sh apps/mbui/scripts/android-ref.sh apps/mbui/scripts/android_ref.py \
    -type f | LC_ALL=C sort | xargs shasum -a 256) || die "what draws the pictures not read"
}
# The screens of NAMEs whose Android pictures are taken anew (ci, REFS=1): in a pull request, of the screens main has
# whose JSON it changed; else (main, after its app changed) every one, REFS_MOST a run in turn by the run's number,
# so a run fits its 10 minutes.
again_of() {
  if [ -n "${GITHUB_BASE_REF:-}" ]; then
    local base=$(git -C $ROOT merge-base origin/main HEAD 2>/dev/null)
    # (one main had a picture of, its JSON changed here: a screen new here has the pictures its runs took)
    for n in "$@"; do git -C $ROOT cat-file -e "$base:client/fixtures/screens/android/$n.png" 2>/dev/null \
      && ! git -C $ROOT diff --quiet "$base" HEAD -- "client/fixtures/screens/$n.json" && echo $n; done
  elif [ $# -gt ${REFS_MOST:-12} ]; then
    local all=$# most=${REFS_MOST:-12}; local from=$(( (${GITHUB_RUN_NUMBER:-0} * most) % all ))
    echo "$@" "$@" | tr ' ' '\n' | tail -n +$((from + 1)) | head -$most
  else
    echo "$@" | tr ' ' '\n'
  fi
}
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
    # (one run of ScreensRefTest a screen, those named: its `screens` argument)
    mkdir -p $O && $ADB shell am instrument -w -e class fail.still.android.motion.ScreensRefTest -e screens "$(echo $names | tr ' ' ',')" \
      $M.test/androidx.test.runner.AndroidJUnitRunner > $O/instrument.log 2>&1
    rm -f $O/refs-failed
    if ! grep -q '^OK (' $O/instrument.log; then
      grep -a -E 'FAILURES|Exception|at fail\.still|Error' $O/instrument.log | head -20
      # (what it drew, to see why: out/android-ref/failed/)
      mkdir -p $O/failed && $ADB pull /sdcard/Android/data/$M/files/screens/. $O/failed > /dev/null 2>&1
      $ADB logcat -d -s StillFailCore:* AndroidRuntime:E System.err:W 2>/dev/null | tail -80 > $O/failed/logcat.txt
      # the screens Android's test could not draw said (out/android-ref/refs-failed), the others' pictures kept
      grep -a -o 'Error in screen\[[^]]*\]' $O/instrument.log | sed 's/.*\[//; s/\]$//' | sort -u > $O/refs-failed
      [ -s $O/refs-failed ] || die "Android's screens not drawn ($O/instrument.log)"
      echo "android-ref: Android's test did not draw: $(tr '\n' ' ' < $O/refs-failed)"
      names=$(for n in $names; do grep -qx "$n" $O/refs-failed || echo $n; done)
      [ -n "$names" ] || die "Android's screens not drawn ($O/instrument.log)"
    fi
    mkdir -p $R
    for n in $names; do
      $ADB pull /sdcard/Android/data/$M/files/screens/$n.png $R/$n.png > $O/pull.log 2>&1 \
        || { cat $O/pull.log; $ADB shell ls -la /sdcard/Android/data/$M/files/screens/; die "$n: no picture"; }
      # (its lines of words, where they stand: compared with the mbui app's by place, not by pixels)
      $ADB pull /sdcard/Android/data/$M/files/screens/$n.texts.json $R/$n.texts.json > $O/pull.log 2>&1 \
        || { cat $O/pull.log; die "$n: no lines of words"; }
    done
    # the system's bars, where the app's window lies under them (the test's word: each screen's alike)
    bars=$($ADB shell cat /sdcard/Android/data/$M/files/screens/$(echo $names | cut -d' ' -f1).bars | tr -d '\r')
    machine | python3 -c 'import json,sys; m=json.load(sys.stdin); t,b=sys.argv[1].split(); m["bars"]={"top":int(t),"bottom":int(b)}; print(json.dumps(m))' "$bars" > $R/android.json
    echo "android-ref: Android's pictures of $(echo $names | wc -w | tr -d ' ') screens in $R, taken on $(cat $R/android.json)"
    ;;
  text)
    # The Android host's text for each screen (screens/text-android.textrec, a section a screen): the mbui app run once
    # on the emulator over the screen's JSON to the moment it names (MBView's shot_at, its own clock), its text and its
    # frames on its log (MBUI_TEXT_RECORD, MBUI_DRAW_LOG); the run's end its own word (SHOT, or its crash: never a
    # time). Only what the Tester then lacks makes this needed (src/sfscreens/android_ref_wbtest.mbt says which).
    [ -n "${MBUI_APK:-}" ] && { $ADB install -r "$MBUI_APK" > /dev/null || die "the mbui app not installed"; }
    uid=$($ADB shell pm list packages -U $PKG | tr -d '\r' | sed -n "s/^package:$PKG uid:\([0-9]*\).*/\1/p")
    mkdir -p $O/text
    # each screen's moment as the Tester takes it (its words on it, then `at`: MBUI_ANDROID_REF=moments), in the window
    # this emulator gives the app (its screen between the bars android.json says, in its density's points)
    [ -f $R/android.json ] || die "no references ($R/android.json): scripts/android-ref.sh refs first"
    win=$(machine | python3 -c 'import json,sys; m=json.load(sys.stdin); b=json.load(open(sys.argv[1]))["bars"]; w,h=map(int,m["size"].split("x")); s=int(m["density"])/160; print(w/s, (h-b["top"]-b["bottom"])/s, s)' $R/android.json)
    t0=$(date +%s)
    (cd $A && MBUI_ANDROID_REF=moments MBUI_ANDROID_WINDOW="$win" moon_test_native -p stillfail/sfscreens 2>&1) > $O/text/moments.txt \
      || { grep -a -E "failed|FAILED" $O/text/moments.txt | head -10; die "the screens' moments not found (src/sfscreens/android_ref_wbtest.mbt)"; }
    echo "android-ref: the screens' moments found in $(($(date +%s) - t0)) s"
    for n in $names; do
      json=$(python3 -c 'import json,sys,base64; print(base64.b64encode(json.dumps(json.load(open(sys.argv[1])),ensure_ascii=False,separators=(",",":")).encode()).decode())' $S/$n.json)
      # (the run to that moment on its clock: MBView draws until its clock reaches it, that frame the last)
      at=$(awk -v n="$n" '$1 == "MOMENT" && $2 == n { printf "%d", ($3 == int($3)) ? $3 : int($3) + 1 }' $O/text/moments.txt)
      [ -n "$at" ] || die "$n: no moment said for it ($O/text/moments.txt)"
      t0=$(date +%s)
      $ADB shell am force-stop $PKG
      $ADB shell run-as $PKG rm -f files/run.log || true
      $ADB logcat -b all -c
      $ADB shell am start -n $PKG/dev.mbui.MainActivity --ei shot_at $at \
        --es env "'MBUI_FIXTURE=json;MBUI_FIXTURE_JSON_B64=$json;MBUI_TEXT_RECORD=1;MBUI_DRAW_LOG=1;MBUI_LOG_FILE=run.log'" > /dev/null
      python3 "$MBUI_DIR/scripts/android_end.py" --adb "$ADB" --app $PKG --uid $uid --file run.log \
        --end "SHOT |FATAL EXCEPTION|Fatal signal" > $O/text/$n.end || { cat $O/text/$n.end; die "$n: no picture's moment"; }
      grep -q "SHOT " $O/text/$n.end || { cat $O/text/$n.end; die "$n: the app ended before its moment"; }
      t1=$(date +%s)
      $ADB exec-out run-as $PKG cat files/run.log > $O/text/$n.log
      $ADB shell am force-stop $PKG
      python3 "$A/scripts/screens.py" keep $n $O/text/$n.log "$A/screens/text-android.textrec" || exit 1
      # (where its time went: the app's run to its moment, then reading its log and keeping its text)
      echo "android-ref: $n: the app's run $((t1 - t0)) s, its text kept $(($(date +%s) - t1)) s"
    done
    ;;
  lists)
    # Each screen's draw list as the Tester draws it over the Android host's text (src/sfscreens/android_ref_wbtest.mbt,
    # MBUI_ANDROID_REF=1: out/android-ref/dl/NAME.dl), and the key of its picture: the draw list's bytes, what draws
    # it (render_code: mbui's renderer, its Android host, how the window is put on the screen) and the references'
    # system (android.json). A picture of that key is the same picture: drawn once, kept (PICS, the Actions cache).
    [ -f $R/android.json ] || die "no references ($R/android.json): scripts/android-ref.sh refs first"
    rm -rf $O/dl && mkdir -p $O/dl
    (cd $A && MBUI_ANDROID_REF=1 moon_test_native -p stillfail/sfscreens 2>&1) > $O/dl/print.txt \
      || { grep -a -E "failed|FAILED|lacks|no Android text" $O/dl/print.txt | head -20; die "the screens' draw lists not drawn (src/sfscreens/android_ref_wbtest.mbt)"; }
    code=$(render_code) && [ -n "$code" ] || die "what draws the pictures not read"
    for n in $names; do
      awk -v n="$n" '$0 == "DLEND " n {p=0} p {print} $0 == "DLBEGIN " n {p=1}' $O/dl/print.txt > $O/dl/$n.dl
      [ -s $O/dl/$n.dl ] || die "$n: no draw list"
      # (the words it drew, a line at a time: compared with Android's by where they stand, android_ref.py)
      sed -n "s/^TEXTRUNS $n //p" $O/dl/print.txt > $O/dl/$n.texts.json
      [ -s $O/dl/$n.texts.json ] || die "$n: no words' lines"
      { cat $O/dl/$n.dl; echo "$code"; cat $R/android.json; } | shasum -a 256 | cut -c1-32 > $O/dl/$n.key
    done
    ;;
  need)
    # the screens whose pictures are not kept (PICS) for their keys (lists): what mbui must draw on the emulator
    for n in $names; do [ -f "$PICS/$(cat $O/dl/$n.key)-$n.png" ] || echo $n; done
    ;;
  mbui)
    # The mbui app's pictures: each screen's draw list (lists) drawn offscreen by mbui-render on the emulator (its GL
    # renderer and its text: RENDER_APK, scripts/render_android.sh's app) into the window's pixels, then put where the
    # window is on the screen (between the bars android.json says) as Android's picture is of the whole screen; a
    # picture kept for its key (PICS) taken as it is, the emulator not asked.
    rm -rf $O/mbui && mkdir -p $O/mbui "$PICS"
    draw=""
    for n in $names; do
      k=$(cat $O/dl/$n.key) || die "$n: no draw list (scripts/android-ref.sh lists)"
      cp $O/dl/$n.texts.json $O/mbui/$n.texts.json
      if [ -f "$PICS/$k-$n.png" ]; then cp "$PICS/$k-$n.png" $O/mbui/$n.png; echo "$n: its picture kept ($k)"; else draw="$draw $n"; fi
    done
    [ -n "$draw" ] || exit 0
    have=$(machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["fingerprint"])')
    want=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["fingerprint"])' $R/android.json)
    [ "$have" = "$want" ] || die "the emulator's system is not the references': this one is $have, they were taken on $want (make them again: the refs job)"
    [ -n "${RENDER_APK:-}" ] && { $ADB install -r "$RENDER_APK" > /dev/null || die "mbui-render not installed"; }
    RID=dev.mbui.demo
    render_uid=$($ADB shell pm list packages -U $RID | tr -d '\r' | sed -n "s/^package:$RID uid:\([0-9]*\)$/\1/p")
    case "$render_uid" in ""|*[!0-9]*) die "mbui-render has no installed uid" ;; esac
    F=/data/user/0/$RID/files
    $ADB shell input keyevent KEYCODE_WAKEUP
    $ADB shell wm dismiss-keyguard
    size=$($ADB shell wm size | sed 's/.*: //' | tr -d '\r')
    top=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["bars"]["top"])' $R/android.json)
    for n in $draw; do
      $ADB shell am force-stop $RID
      $ADB shell run-as $RID mkdir -p files
      $ADB shell run-as $RID rm -f files/$n.png
      $ADB exec-in "run-as $RID sh -c 'cat > files/$n.dl'" < $O/dl/$n.dl
      $ADB logcat -c
      $ADB shell am start -n $RID/dev.mbui.MainActivity --es env "'MBUI_DL=$F/$n.dl;MBUI_DL_PNG=$F/$n.png'" > /dev/null
      # Only this renderer's completion or crash; a system app's crash says nothing about this picture.
      said=$($ADB logcat --uid="$render_uid" -v brief -e 'mbui-render: |FATAL EXCEPTION|Fatal signal' -m 1 | grep -v '^-----')
      case "$said" in
        *"mbui-render: "*"instances"*) ;;
        *) echo "$said"; $ADB logcat -d -t 200 | tail -40; die "$n: not drawn" ;;
      esac
      $ADB exec-out run-as $RID cat files/$n.png > $O/mbui/$n.window.png
      python3 "$D/android_ref.py" place $O/mbui/$n.window.png $O/mbui/$n.png ${size%x*} ${size#*x} $top || exit 1
      cp $O/mbui/$n.png "$PICS/$(cat $O/dl/$n.key)-$n.png"
      echo "$n: drawn ($said)"
    done
    $ADB shell am force-stop $RID
    ;;
  compare)
    python3 "$D/android_ref.py" "$R" "$O/mbui" "$O" "$S/allowed.json" $names
    ;;
  plan)
    # the screens whose Android pictures a CI run takes (ci, REFS=1): those with none yet, REFS_MOST of them; else in a
    # pull request those main has a picture of whose JSON it changed, on main every one in turn; none, nothing of
    # Android's to build or draw (mbui-android-ref.yml's `what`)
    fresh=$(for n in $names; do [ -f $R/$n.png ] || echo $n; done)
    if [ -n "$fresh" ]; then echo $fresh | tr ' ' '\n' | head -${REFS_MOST:-12}; exit 0; fi
    again_of $names
    ;;
  ci)
    # CI's run (mbui-android-ref.yml: every screen): the runner's CPU said (the emulator draws in software on it); Android's
    # pictures taken anew where its app or the screens changed (REFS=1), held to those kept (a change is a new
    # reference: this run's, committed in its PR); then the mbui app's, compared
    fail=0
    echo "android-ref: on $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')"
    # Screens with no Android picture yet (new ones): theirs taken a few a run (REFS_MOST: Android's test draws them one
    # after another, its app built first, in the job's 10 minutes), nothing else done in it, the run failing until
    # every one is in (each run's committed in the PR from its artifact)
    fresh=$(for n in $names; do [ -f $R/$n.png ] || echo $n; done)
    if [ -n "$fresh" ]; then
      take=$(echo $fresh | tr ' ' '\n' | head -${REFS_MOST:-12} | tr '\n' ' ')
      [ -n "${ANDROID_APK:-}" ] || die "new screens ($take) and no Android app to take their pictures (REFS: the workflow builds it)"
      bash "$0" refs $take || exit 1
      left=$(( $(echo $fresh | wc -w) - $(echo $take | wc -w) ))
      echo "android-ref: Android's pictures of new screens taken ($take): commit this run's (its artifact's client/fixtures/screens/android) in the PR; $left more to take after"
      exit 1
    fi
    # (Android's pictures taken anew: in a pull request, of the screens main has whose JSON it changed; after its app changed,
    # every one, REFS_MOST a run in turn by the run's number, so a run fits its 10 minutes)
    again=$(again_of $names | tr '\n' ' ')
    # (Android's system as the pictures kept have it: the draw lists, made for it, made again only if it changed)
    system=$(cat $R/android.json 2>/dev/null)
    if { [ "${REFS:-}" = 1 ] && [ -n "$(echo $again)" ]; } || [ ! -f $R/android.json ]; then
      rm -rf $O/kept && mkdir -p $O && { [ -f $R/android.json ] && cp -r $R $O/kept; true; }
      all_names=$names
      names=$again
      bash "$0" refs $names || exit 1
      # (those Android's test could not draw: said, failing the run, and left out of what follows)
      if [ -s $O/refs-failed ]; then
        fail=1
        names=$(for n in $names; do grep -qx "$n" $O/refs-failed || echo $n; done)
      fi
      # held to those kept as android_ref.py compares (a channel a step apart the same: the same picture has come out so
      # on another runner, at circles' edges), the kept ones then left as they are
      if [ -f $O/kept/android.json ] && cmp -s $O/kept/android.json $R/android.json \
        && python3 "$D/android_ref.py" "$O/kept" "$R" "$O/kept-diff" /nonexistent $names > /dev/null; then
        (cd $ROOT && git checkout -- client/fixtures/screens/android)
        # (said for the job: pictures taken over this code, these screens and this emulator are the ones kept)
        echo same > $O/refs-same
      else
        echo "android-ref: Android's pictures are not the ones kept: commit this run's (its artifact's client/fixtures/screens/android) in the PR"
        [ -f $O/kept/android.json ] && python3 "$D/android_ref.py" "$O/kept" "$R" "$O/kept-diff" /nonexistent $names | grep '^| [a-z]'
        fail=1
        # new ones taken again, to be references (one that differs from itself is none: the run says where); those the
        # same as kept need not be, the kept ones having been so
        rm -rf $O/again && cp -r $R $O/again
        bash "$0" refs $names > /dev/null || exit 1
        python3 "$D/android_ref.py" "$O/again" "$R" "$O/again-diff" /nonexistent $names | grep '^| [a-z]' \
          | sed 's/^/android-ref: Android twice: /'
      fi
      # (every screen compared after, those taken anew and the rest; one Android's test could not draw left out)
      names=$(for n in $all_names; do [ -s $O/refs-failed ] && grep -qx "$n" $O/refs-failed || echo $n; done)
    fi
    # the Android host's text the Tester lacks, recorded (TEXT=1: the job found it lacking), then kept in the PR
    # (nothing compared after it: the run fails for the text to be committed, and the next compares over it; the job
    # has 10 minutes, and recording, the draw lists again, drawing and comparing them took more: 39773993975)
    if [ "${TEXT:-}" = 1 ]; then
      # (the screens with no section of their own yet, where there are such: a new screen's alone, not every screen's
      # again; recording chat-cards alone took 3 minutes, 39854585955)
      lacking=$(for n in $names; do grep -q "^# $n " "$A/screens/text-android.textrec" || echo $n; done)
      # (and a screen whose section lacks what the Tester asked of it, as the draw lists said: one with words set anew,
      # its title's spacing; the first of them, the test stopping there, the next in the run after)
      [ -n "$lacking" ] || lacking=$(grep -a -oE "FAILED: [a-z0-9-]+: the Android text lacks" $O/dl/print.txt 2>/dev/null \
        | sed 's/^FAILED: //; s/: the Android text lacks$//' | sort -u)
      bash "$0" text ${lacking:-$names} || exit 1
      echo "android-ref: the Android text recorded anew: commit this run's screens/text-android.textrec (its artifact) in the PR"
      exit 1
    fi
    # (the draw lists again where the text was recorded anew or Android's system changed with its pictures: not for
    # pictures taken over the same system, which left the draw lists as they were, 39926112139)
    { [ "${TEXT:-}" = 1 ] || [ "$(cat $R/android.json 2>/dev/null)" != "${system:-}" ] || [ ! -f $O/dl/print.txt ]; } \
      && { bash "$0" lists $names || exit 1; }
    bash "$0" mbui $names || exit 1
    bash "$0" compare $names || fail=1
    exit $fail
    ;;
  *) die "refs, mbui or compare (scripts/android-ref.sh)" ;;
esac
