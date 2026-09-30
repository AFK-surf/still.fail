#!/bin/sh
# The motion tests (kotlin/fail/still/android/motion), on studio's emulator-5600, under the emulator's shared lock:
#   sh apps/android/app/src/androidTest/motion.sh [class[#method]] [out]
# e.g. fail.still.android.motion.ChatMotionTest#outboxBecomesTheMessage. The app is built as fail.still.android.motion
# (-PmotionTest), an app of its own beside the signed-in one, and taken off again after. Each recording comes out in
# <out>/<name>/ (default /tmp/motion-out): its frames, settled.png, strip.png, diff.csv (Harness.kt), and two videos,
# normal.webm (60 fps) and slow.webm (a tenth of the speed); NOVIDEO=1 skips the videos.
set -e
cd "$(dirname "$0")/../../.."
. ~/ember-wt/env.sh
export JAVA_HOME=$(/usr/libexec/java_home)
CLASS=${1:-fail.still.android.motion}
OUT=${2:-/tmp/motion-out}
A="adb -s emulator-5600"
ID=fail.still.android.motion
./gradlew -q --no-watch-fs -PmotionTest :app:assembleDebug :app:assembleDebugAndroidTest
until mkdir /tmp/act-emu.lock 2>/dev/null; do sleep 2; done
trap 'rmdir /tmp/act-emu.lock' EXIT
$A install -r -t app/build/outputs/apk/debug/app-debug.apk >/dev/null
$A install -r -t app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk >/dev/null
$A shell rm -rf /sdcard/Android/data/$ID/files/motion
case "$CLASS" in *.*[A-Z]*) SEL="-e class $CLASS" ;; *) SEL="-e package $CLASS" ;; esac
$A shell am instrument -w $SEL $ID.test/androidx.test.runner.AndroidJUnitRunner | grep -vE '^INSTRUMENTATION_STATUS(_CODE)?: ?(class|current|id|numtests|stream=$|test)' || true
rm -rf "$OUT"; mkdir -p "$OUT"
$A pull /sdcard/Android/data/$ID/files/motion/. "$OUT" >/dev/null
$A shell rm -rf /sdcard/Android/data/$ID/files/motion
$A uninstall $ID.test >/dev/null; $A uninstall $ID >/dev/null
rmdir /tmp/act-emu.lock; trap - EXIT
# NOVIDEO=1: frames, strips and differences only (the videos take a few minutes).
[ -n "$NOVIDEO" ] && { ls "$OUT"; exit 0; }
FF=$(ls -d ~/Library/Caches/ms-playwright/ffmpeg-*/ffmpeg-mac | head -1)
for d in "$OUT"/*/; do
  cat "$d"f*.jpg > "$d"frames.mjpeg
  "$FF" -loglevel error -y -f image2pipe -r 60 -c:v mjpeg -i "$d"frames.mjpeg -vf scale=540:-2 -c:v libvpx -b:v 3M "$d"normal.webm
  "$FF" -loglevel error -y -f image2pipe -r 6 -c:v mjpeg -i "$d"frames.mjpeg -vf scale=540:-2 -r 30 -c:v libvpx -b:v 3M "$d"slow.webm
  rm "$d"frames.mjpeg
done
ls "$OUT"
