#!/bin/bash
# The React Native app on the devenv's emulator (ref.sh's, up), quickly: built for the dev cloud (unless BUILD=0),
# installed, started, signed in as alice if it asks, then what JS said (errors with their stacks read against the
# bundle's map) and a screenshot. For finding why it does not get to its pages, before shots.sh.
#
#   bash apps/mobile-rn/scripts/devenv/try.sh [out dir]
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
APP=$(cd "$HERE/../.." && pwd)
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export ANDROID_SERIAL=${ANDROID_SERIAL:-emulator-5698}
OUT=${1:-$APP/try}
mkdir -p "$OUT"
UI=$OUT/.ui.xml
a() { "$SDK/platform-tools/adb" "$@" < /dev/null; }
dump() { a shell uiautomator dump /sdcard/devenv-ui.xml > /dev/null 2>&1; a exec-out cat /sdcard/devenv-ui.xml > "$UI" 2> /dev/null; }
at() { python3 "$HERE/ui.py" "$UI" "$@"; }

if [ "${BUILD:-1}" != 0 ]; then
  EXPO_PUBLIC_STILLFAIL_CLOUD=http://127.0.0.1:${PORT:-8930} bash "$APP/scripts/android.sh" > "$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; exit 1; }
fi
APK=$APP/android/app/build/outputs/apk/release/app-release.apk
MAP=$APP/android/app/build/generated/sourcemaps/react/release/index.android.bundle.map
a install -r "$APK" > /dev/null
a reverse tcp:${PORT:-8930} tcp:${PORT:-8930} > /dev/null
a reverse tcp:3340 tcp:3340 > /dev/null
a logcat -c
a shell am force-stop fail.still.rntrial
a shell am start -n fail.still.rntrial/.MainActivity > /dev/null
sleep 8
dump
if xy=$(at "~用开发账号登录（alice" "~Dev sign-in (alice"); then a shell input tap $xy; sleep 12; fi
a exec-out screencap -p > "$OUT/now.png"
a logcat -d -v raw -s ReactNativeJS:V AndroidRuntime:E > "$OUT/js.txt"
(cd "$APP" && npx metro-symbolicate "$MAP" < "$OUT/js.txt" 2>&1) \
  | grep -v "node_modules/react-native/\|Linking found\|Using 'still\|Provide the preferred\|OTA " | awk '!seen[$0]++' | head -${LINES_OUT:-60} | cut -c1-400
