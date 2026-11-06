#!/bin/bash
# No device needed: reject physical devices at both public entry points before installation, input, file changes
# or log clearing. A synthetic emulator reaches its first write only through adb -s with the verified serial.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$D/../out"
T=$(mktemp -d "$D/../out/render-device-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
cat > "$T/adb" <<'ADB'
#!/bin/bash
set -eu
printf 'CALL %s\n' "$*" >> "$FAKE_ADB_LOG"
if [ "$*" = '-e get-serialno' ]; then
  printf '%s\n' "$FAKE_SERIAL"
  exit 0
fi
if [ "$1" = -s ]; then shift 2; fi
case "$*" in
  'shell getprop ro.kernel.qemu') printf '%s\n' "$FAKE_QEMU" ;;
  'shell pm list packages -U dev.mbui.demo') echo 'package:dev.mbui.demo uid:10123' ;;
  *) printf 'WRITE %s\n' "$*" >> "$FAKE_ADB_LOG"; exit 77 ;;
esac
ADB
chmod +x "$T/adb"
export ADB="$T/adb" FAKE_ADB_LOG="$T/calls.log"
for entry in render_android.sh render_paint_damage_android.sh; do
  for scenario in explicit-physical default-physical wrong-emulator; do
    export FAKE_SERIAL=physical-device FAKE_QEMU=1 ANDROID_SERIAL=
    case "$scenario" in
      explicit-physical) export ANDROID_SERIAL=physical-device ;;
      wrong-emulator) export ANDROID_SERIAL=emulator-5554 FAKE_QEMU=0 ;;
    esac
    : > "$FAKE_ADB_LOG"
    code=0
    bash "$D/$entry" run > "$T/result.log" 2>&1 || code=$?
    [ "$code" = 1 ] && ! grep -q '^WRITE ' "$FAKE_ADB_LOG" || {
      echo "render device: $entry failed to reject $scenario before writes (exit $code)"
      cat "$T/result.log" "$FAKE_ADB_LOG"
      exit 1
    }
  done
  for selected in '' emulator-5554; do
    export ANDROID_SERIAL="$selected" FAKE_SERIAL=emulator-5554 FAKE_QEMU=1
    : > "$FAKE_ADB_LOG"
    code=0
    bash "$D/$entry" run > "$T/result.log" 2>&1 || code=$?
    # The stub stops at the first write. Both selection paths must reach it, always pinned to the checked serial.
    [ "$code" = 77 ] && grep -q '^CALL -s emulator-5554 shell getprop ro.kernel.qemu$' "$FAKE_ADB_LOG" &&
      grep -q '^WRITE ' "$FAKE_ADB_LOG" &&
      ! grep '^CALL ' "$FAKE_ADB_LOG" | grep -v '^CALL -s emulator-5554 ' | grep -v '^CALL -e get-serialno$' || {
        cat "$T/result.log" "$FAKE_ADB_LOG"; exit 1;
      }
  done
done
echo 'render device: both entry points reject physical devices before writes and pin the verified emulator'
