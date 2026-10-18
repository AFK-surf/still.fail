#!/bin/bash
# Android: build libmbui.so from the C that moon generates plus the runtime
# and src/host/android_host.c, package it with Gradle, and run it on an
# emulator of our own (AVD mbui-avd, port 5580).
#   scripts/android.sh build | emu | run [script] | shot NAME | stop | delete
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
SDK=$HOME/Library/Android/sdk
NDK=$SDK/ndk/28.2.13676358
TC=$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin
CC="$TC/aarch64-linux-android29-clang"
ADB=$SDK/platform-tools/adb
AVD=mbui-avd
PORT=5580
SERIAL=emulator-$PORT
OUT=out/android
export JAVA_HOME=$(/usr/libexec/java_home -v 20 2>/dev/null || /usr/libexec/java_home)
export ANDROID_HOME=$SDK
CFLAGS="-I$MOON_HOME/include -Isrc/host -fPIC -fwrapv -fno-strict-aliasing -Wno-unused-value -O2 -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_SYSTEM"

case "${1:-build}" in
  build)
    T0=$(python3 -c 'import time;print(time.time())')
    moon build --target native --release 2>&1 | python3 "$D/errs.py" | grep -v '^errors: 0' || true
    mkdir -p $OUT/obj android/app/src/main/jniLibs/arm64-v8a
    $CC $CFLAGS -Dmain=mbui_main -c _build/native/release/build/demo/demo.c -o $OUT/obj/demo.o
    for f in runtime env utf sync_io backtrace; do
      $CC $CFLAGS -c $MOON_HOME/lib/runtime/$f.c -o $OUT/obj/rt_$f.o 2>$OUT/rt_$f.err \
        || { echo "skip runtime/$f.c: $(grep error $OUT/rt_$f.err | head -1)"; rm -f $OUT/obj/rt_$f.o; }
    done
    $CC $CFLAGS -c src/host/android_host.c -o $OUT/obj/android_host.o
    $CC -shared -o android/app/src/main/jniLibs/arm64-v8a/libmbui.so $OUT/obj/*.o \
      -lGLESv3 -llog -lm -Wl,--no-undefined
    T1=$(python3 -c 'import time;print(time.time())')
    echo "libmbui.so $(stat -f %z android/app/src/main/jniLibs/arm64-v8a/libmbui.so) bytes in $(python3 -c "print(round($T1-$T0,2))") s"
    (cd android && ./gradlew --no-daemon -q assembleDebug 2>&1 | grep -v '^$' | tail -20)
    ls -la android/app/build/outputs/apk/debug/*.apk
    ;;
  emu)
    if ! $SDK/emulator/emulator -list-avds | grep -qx $AVD; then
      IMG=$(ls -d $SDK/system-images/android-3*/google_apis*/arm64-v8a 2>/dev/null | sort | tail -1)
      PKG="system-images;$(echo $IMG | sed "s|$SDK/system-images/||; s|/|;|g")"
      echo "creating $AVD from $PKG"
      echo no | $SDK/cmdline-tools/latest/bin/avdmanager create avd -n $AVD -k "$PKG" -d pixel_7 >/dev/null
    fi
    if ! $ADB devices | grep -q "^$SERIAL"; then
      nohup $SDK/emulator/emulator -avd $AVD -port $PORT -no-window -no-audio -no-boot-anim \
        -gpu swiftshader_indirect -no-snapshot >$OUT/emu.log 2>&1 &
    fi
    $ADB -s $SERIAL wait-for-device
    until [ "$($ADB -s $SERIAL shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 2; done
    echo "emulator ready"
    ;;
  run)
    $ADB -s $SERIAL install -r android/app/build/outputs/apk/debug/app-debug.apk >/dev/null
    $ADB -s $SERIAL shell am force-stop dev.mbui.demo
    if [ -n "${2:-}" ]; then
      $ADB -s $SERIAL shell am start -n dev.mbui.demo/dev.mbui.MainActivity --es script "$2" >/dev/null
    else
      $ADB -s $SERIAL shell am start -n dev.mbui.demo/dev.mbui.MainActivity ${BENCH:+--ei bench $BENCH} >/dev/null
    fi
    ;;
  shot)
    mkdir -p $OUT/shots
    $ADB -s $SERIAL exec-out screencap -p > $OUT/shots/$2.png && echo "shot $OUT/shots/$2.png"
    ;;
  log)
    $ADB -s $SERIAL logcat -d -s mbui:I AndroidRuntime:E DEBUG:* libc:* | tail -${2:-40}
    ;;
  stop)
    $ADB -s $SERIAL emu kill 2>/dev/null || true
    ;;
  delete)
    $ADB -s $SERIAL emu kill 2>/dev/null || true
    sleep 3
    $SDK/cmdline-tools/latest/bin/avdmanager delete avd -n $AVD
    ;;
esac
