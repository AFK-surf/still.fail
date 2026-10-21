#!/bin/bash
# The emulator booted (action.yml): KVM for the runner's user, an AVD over the cached system image, the cached
# emulator started in the background (its log in $RUNNER_TEMP/emulator.log), and until it says the boot completed or
# it ends first (said, with its log): as they come; BOOT_MOST the most a boot that hangs is given, said where it stood.
set -euo pipefail
SDK=${ANDROID_HOME:-/usr/local/lib/android/sdk}
EMU=$HOME/android-emu/emulator/emulator
IMAGE="system-images;android-34;$TARGET;x86_64"
[ -x "$EMU" ] || { echo "::error::no emulator build 16428233 in the Actions cache: run the android-sdk workflow"; exit 1; }
[ -f "$SDK/system-images/android-34/$TARGET/x86_64/system.img" ] ||
  { echo "::error::no $IMAGE in the Actions cache: run the android-sdk workflow"; exit 1; }
echo "emulator: $(grep -a '^Pkg.Revision' "$HOME/android-emu/emulator/source.properties"); image: $IMAGE ($IMG)"
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm
# (one AVD home for the two: avdmanager's and the emulator's, as android-emulator-runner had it)
export ANDROID_AVD_HOME=$HOME/.android/avd
mkdir -p "$ANDROID_AVD_HOME"
echo no | "$SDK/cmdline-tools/latest/bin/avdmanager" create avd --force -n ci --package "$IMAGE" --device "$PROFILE" > "$RUNNER_TEMP/avd.log" 2>&1 ||
  { cat "$RUNNER_TEMP/avd.log"; exit 1; }
[ -f "$ANDROID_AVD_HOME/ci.ini" ] || { echo "::error::avdmanager made no ci.ini in $ANDROID_AVD_HOME"; cat "$RUNNER_TEMP/avd.log"; ls -la ~/.android ~/.config/.android 2>/dev/null; exit 1; }
ADB=$SDK/platform-tools/adb
ANDROID_SDK_ROOT=$SDK "$EMU" -avd ci -port 5554 -no-window -gpu swiftshader_indirect -no-snapshot -noaudio \
  -no-boot-anim > "$RUNNER_TEMP/emulator.log" 2>&1 &
E=$!
echo "emulator pid $E"
# up: the emulator's own word, "Boot completed in N ms" on its log (it says so as the system sets sys.boot_completed;
# the system's events buffer is no witness: the emulator resizes it then, which empties it), followed as the log is
# written (tail -f: inotify); or the emulator's end first, which fails saying its log, never left waiting
( grep -a -m 1 'Boot completed' <(tail -n +1 -f "$RUNNER_TEMP/emulator.log") && $ADB -s emulator-5554 wait-for-device ) &
W=$!
# (the most a boot that hangs is given, BOOT_MOST s, 600: not a wait, its end fails saying where the boot stood)
( sleep "${BOOT_MOST:-600}" ) &
T=$!
set +e
wait -n $E $W $T
first=$?
set -e
if ! kill -0 $W 2>/dev/null && kill -0 $E 2>/dev/null && [ $first = 0 ]; then
  kill $T 2>/dev/null || true
  echo "booted"
else
  if kill -0 $E 2>/dev/null; then
    echo "::error::the emulator not up after ${BOOT_MOST:-600} s"
  else
    echo "::error::the emulator ended before it was up (exit $first)"
  fi
  echo "--- emulator.log"; tail -60 "$RUNNER_TEMP/emulator.log"
  echo "--- adb devices"; $ADB devices -l || true
  echo "--- boot"; $ADB -s emulator-5554 shell 'getprop sys.boot_completed; getprop init.svc.bootanim' 2>&1 || true
  echo "--- events"; $ADB -s emulator-5554 logcat -b events -d -v brief 2>&1 | grep -a boot_progress | tail -20 || true
  kill $W $T 2>/dev/null || true
  exit 1
fi
if [ "$ANIMATIONS" = false ]; then
  for k in window_animation_scale transition_animation_scale animator_duration_scale; do
    $ADB -s emulator-5554 shell settings put global $k 0
  done
fi
$ADB -s emulator-5554 shell input keyevent 82 || true
echo "booted: $($ADB -s emulator-5554 shell getprop ro.build.fingerprint | tr -d '\r')"
