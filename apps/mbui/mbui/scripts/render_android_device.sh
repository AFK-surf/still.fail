# Sourced by both Android rendering entry points. Select and verify the emulator before any device writes; every
# later adb command stays on that serial even when a physical device is connected alongside it.
render_adb() { "$ADB" -s "$render_android_serial" "$@"; }

render_android_device() {
  render_android_serial=${ANDROID_SERIAL:-}
  if [ -z "$render_android_serial" ]; then
    render_android_serial=$("$ADB" -e get-serialno) || {
      echo "render_android: select one emulator with ANDROID_SERIAL" >&2
      return 1
    }
  fi
  if [[ ! "$render_android_serial" =~ ^emulator-[0-9]+$ ]]; then
    echo "render_android: only an emulator serial is accepted" >&2
    return 1
  fi
  local qemu
  qemu=$(render_adb shell getprop ro.kernel.qemu | tr -d '\r')
  if [ "$qemu" != 1 ]; then
    echo "render_android: the selected device did not identify itself as an emulator" >&2
    return 1
  fi
  export ANDROID_SERIAL="$render_android_serial"
}
