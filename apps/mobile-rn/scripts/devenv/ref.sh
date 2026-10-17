#!/bin/bash
# The Android app's reference screenshots (ref/ here), on studio: the app built for the dev environment's cloud (the
# motion test variant, fail.still.android.motion, which installs beside the others), on an emulator of its own (AVD
# rn-ref, port 5698, no window; others on studio are other people's), Chinese, signed in through its dev sign-in, then
# shots.sh. up.sh first.
#
#   bash apps/mobile-rn/scripts/devenv/ref.sh          build (unless BUILD=0), emulator, install, screenshots
#   bash apps/mobile-rn/scripts/devenv/ref.sh stop     the emulator stopped and the AVD deleted
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export JAVA_HOME=${JAVA_HOME:-$HOME/.sdkman/candidates/java/17.0.18-tem} ANDROID_HOME=$SDK
PORT=${PORT:-8930}
EPORT=5698
AVD=rn-ref
export ANDROID_SERIAL=emulator-$EPORT
a() { "$SDK/platform-tools/adb" "$@" < /dev/null; }
avdmanager() { "$(ls "$SDK"/cmdline-tools/*/bin/avdmanager | head -1)" "$@"; }
ours() { [ "$(a emu avd name 2> /dev/null | head -1 | tr -d '\r')" = "$AVD" ]; }

if [ "${1:-}" = stop ]; then
  if ours; then a emu kill || true; sleep 3; fi
  avdmanager delete avd -n "$AVD" > /dev/null 2>&1 || true
  echo "emulator stopped, AVD $AVD deleted"
  exit 0
fi

# APK, ACTIVITY, OUT: another app's screenshots the same way (the React Native app: BUILD=0, its APK and activity).
APK=${APK:-$ROOT/apps/android/app/build/outputs/apk/debug/app-debug.apk}
if [ "${BUILD:-1}" != 0 ]; then
  (cd "$ROOT" && { [ -d .git ] || { git init -q && git add -A && git -c user.email=devenv@local -c user.name=devenv commit -qm mirror --no-verify; }; })
  echo "sdk.dir=$SDK" > "$ROOT/apps/android/local.properties"
  python3 "$ROOT/apps/android/build.py" --tasks > "$HERE/state/android-build.log" 2>&1
  (cd "$ROOT/apps/android" && ./gradlew --no-watch-fs --console=plain -q -PmotionTest -PstillfailPrebuiltEngine -PstillfailCloud=http://127.0.0.1:$PORT :app:assembleDebug >> "$HERE/state/android-build.log" 2>&1)
fi

# ── the emulator ──
if ! ours; then
  if a devices | grep -q "^emulator-$EPORT"; then echo "emulator-$EPORT is someone else's" >&2; exit 1; fi
  [ -d ~/.android/avd/$AVD.avd ] || echo no | avdmanager create avd -n "$AVD" -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_7 > /dev/null
  # In a session of its own: the task or shell that started it ending does not take it down.
  ANDROID_SDK_ROOT=$SDK python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$SDK/emulator/emulator" -avd "$AVD" -no-window -no-audio -no-boot-anim -no-snapshot -port $EPORT > "$HERE/state/emulator.log" 2>&1 < /dev/null &
  disown
  a wait-for-device
  for i in $(seq 1 120); do [ "$(a shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = 1 ] && break; sleep 2; done
  ours || { echo "emulator-$EPORT is not $AVD" >&2; exit 1; }
  # Chinese, as the people using it have it.
  a root > /dev/null; sleep 2
  a shell setprop persist.sys.locale zh-CN
  a shell setprop ctl.restart zygote
  sleep 5
  for i in $(seq 1 60); do [ "$(a shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = 1 ] && a shell pm path android > /dev/null 2>&1 && break; sleep 2; done
  sleep 10
fi
a install -r -t -d "$APK" > /dev/null
a reverse tcp:$PORT tcp:$PORT
a reverse tcp:3340 tcp:3340
bash "$HERE/shots.sh" "${ACTIVITY:-fail.still.android.motion/fail.still.android.MainActivity}" "${OUT:-$HERE/ref}"
