#!/bin/bash
# This trial's own emulator on studio (AVD rn-trial, port 5696: the others there are other chats'), started if it is
# not up; then, given an APK, installs it and starts the app. `shot <file>`: a screenshot. `stop`: ends it and drops the AVD.
set -euo pipefail
S=${ANDROID_HOME:-$HOME/Library/Android/sdk}; export ANDROID_SERIAL=emulator-5696; A=$S/platform-tools/adb
export JAVA_HOME=${JAVA_HOME:-$HOME/.sdkman/candidates/java/17.0.18-tem}
AVD=rn-trial
case "${1:-}" in
  stop) $A emu kill || true; sleep 2; $(ls $S/cmdline-tools/*/bin/avdmanager | head -1) delete avd -n $AVD || true; exit 0 ;;
  shot) $A exec-out screencap -p > "$2"; exit 0 ;;
esac
if ! $A get-state > /dev/null 2>&1; then
  [ -d ~/.android/avd/$AVD.avd ] || echo no | $(ls $S/cmdline-tools/*/bin/avdmanager | head -1) create avd -n $AVD -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_7 > /dev/null 2>&1 || true
  ANDROID_SDK_ROOT=$S nohup $S/emulator/emulator -avd $AVD -no-window -no-audio -no-boot-anim -no-snapshot-save -port 5696 > /tmp/rn-trial-emu.log 2>&1 < /dev/null &
  $A wait-for-device
  for i in $(seq 1 90); do [ "$($A shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break; sleep 2; done
fi
if [ -n "${1:-}" ]; then
  $A install -r "$1" > /dev/null
  $A shell am force-stop fail.still.rntrial
  $A logcat -c
  $A shell am start -n fail.still.rntrial/.MainActivity > /dev/null
fi
