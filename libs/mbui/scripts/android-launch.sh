#!/bin/bash
# The app (built already: scripts/android.sh build) started on the emulator scripts/android.sh runs (EMU_PORT as
# there) and its first frame on the screen, or its crash: what CI's oldest Android (minSdk's, API 30) runs, so a call
# the system there does not have (API 34's Paint.getFontMetricsInt run overload aborted every start below Android 14,
# #2665) fails here, not on a person's phone.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
ADB=${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb
S=emulator-${EMU_PORT:-5580}
APP_ID=${MBUI_APP_ID:-dev.mbui.demo}
echo "Android $($ADB -s $S shell getprop ro.build.version.release | tr -d '\r') (API $($ADB -s $S shell getprop ro.build.version.sdk | tr -d '\r'))"
$ADB -s $S logcat -c
# the app's frames on its own clock to the one at 100 ms (MBView's shot_at), which it says once it is on the screen
# ("SHOT n t"); or the app's end first, as the system logs it: a native one only if it is the app's process (the
# signal's line names the process that got it: the emulator's own traced_probes aborted as the app started, said
# here as the app's crash, scheduled mbui-ci 42751498360, 2026-11-10)
SHOT_AT=100 bash "$D/android.sh" run
said=$($ADB -s $S logcat -v brief -m 1 -e "SHOT [0-9]+ [0-9]|FATAL EXCEPTION|Fatal signal .*pid [0-9]+ \\(${APP_ID//./\\.}")
if [[ $said == *"SHOT "* ]]; then
  echo "launch: first frame shown ($said)"
  exit 0
fi
echo "::error::the app crashed as it started on API $($ADB -s $S shell getprop ro.build.version.sdk | tr -d '\r')"
$ADB -s $S logcat -d -v brief | grep -a -E "FATAL|Fatal signal|Abort message|NoSuchMethod|AndroidRuntime|JNI DETECTED" | head -40
exit 1
