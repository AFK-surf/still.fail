#!/bin/bash
# Android: build libmbui.so from the C that moon generates plus the runtime
# and src/host/android_host.c, package it with Gradle, and run it on an
# emulator of our own (AVD mbui-avd, port 5580). APP=demo|photos|coredemo|stillfail|sffix picks the app (coredemo and
# stillfail with the still.fail core in them);
# ENV="K=V;K2=V2" gives `run` the app's environment variables (MainActivity sets them before the app starts).
#   scripts/android.sh build | emu | run [script] | shot NAME | log | listen-test | stop | delete
# moon.pkg cannot choose files per OS, so the build runs on a copy of the
# module in out/android/mod, where photos shows src/photos/pictures/android.mbt.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
# Studio's SDK, or the one the machine says (CI: ANDROID_HOME, ANDROID_NDK_LATEST_HOME)
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
NDK=${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-$SDK/ndk/28.2.13676358}}
HOST_TAG=$([ "$(uname)" = Darwin ] && echo darwin-x86_64 || echo linux-x86_64)
TC=$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin
CC="$TC/aarch64-linux-android29-clang"
ADB=$SDK/platform-tools/adb
AVD=${AVD:-mbui-avd}
PORT=${EMU_PORT:-5580}
SERIAL=emulator-$PORT
OUT=out/android
PKG=${APP:-demo}
M=$OUT/mod
[ -x /usr/libexec/java_home ] && export JAVA_HOME=$(/usr/libexec/java_home -v 20 2>/dev/null || /usr/libexec/java_home)
export ANDROID_HOME=$SDK
size() { wc -c < "$1" | tr -d ' '; }
CFLAGS="-I$MOON_HOME/include -Isrc/host -fPIC -fwrapv -fno-strict-aliasing -Wno-unused-value -O2 -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_SYSTEM"

sync() {
  mkdir -p $M/src
  cp -p moon.mod $M/
  cp -rp src/. $M/src/
  cp -p src/photos/pictures/android.mbt $M/src/photos/pictures_native.mbt
  # moon still links a (macOS) program of the copy, which nothing runs: only its C is taken. The apps with the core
  # need the Apple shell (scripts/core.sh shell), which an Android build has no use for; its symbols are left unresolved.
  for app in coredemo stillfail; do
    sed -e 's|out/core/aarch64-apple-darwin/libstillfail_shell.a|-Wl,-undefined,dynamic_lookup|' \
      src/$app/moon.pkg > $M/src/$app/moon.pkg
    if ! grep -q dynamic_lookup $M/src/$app/moon.pkg; then
      echo "android.sh: src/$app/moon.pkg no longer links the shell as expected" >&2
      exit 1
    fi
  done
}

# the photos app's pictures (see pictures/android.mbt): copied into the
# app's files, and one served over http to the emulator's 10.0.2.2 (on 5590:
# the emulator itself takes 5580 and 5581)
photos() {
  P=$OUT/photos
  if [ ! -f $P/11.jpg ]; then
    mkdir -p $P
    i=0
    for f in "/System/Library/Desktop Pictures/.thumbnails/"*.heic; do
      [ $i -lt 12 ] || break
      sips -s format jpeg "$f" --out $P/$i.jpg >/dev/null && i=$((i + 1))
    done
    cp "/System/Library/Desktop Pictures/iMac Blue.heic" $P/big.heic
    sips -s format jpeg "/System/Library/Desktop Pictures/iMac Orange.heic" --out $P/big.jpg >/dev/null
  fi
  cp -p test/images/*.jpg $P/
  $ADB -s $SERIAL shell run-as dev.mbui.demo mkdir -p files/photos
  for f in $P/*.jpg $P/*.heic; do
    $ADB -s $SERIAL exec-in "run-as dev.mbui.demo sh -c 'cat > files/photos/$(basename $f)'" < $f
  done
  if ! curl -s -o /dev/null http://127.0.0.1:5590/; then
    nohup python3 -m http.server 5590 --bind 127.0.0.1 -d $P >$OUT/http.log 2>&1 &
    echo $! > $OUT/http.pid
  fi
}

# A .so of an AAR on Maven Central (GROUP/ARTIFACT VERSION FILE LIB), from Gradle's cache when it has it, into $jni.
aar_lib() {
  local aar=$(ls $HOME/.gradle/caches/modules-2/files-2.1/$1/$2/*/$3 2>/dev/null | head -1)
  if [ -z "$aar" ]; then
    aar=$OUT/$3
    [ -f $aar ] || curl -sSfL -o $aar https://repo1.maven.org/maven2/$(echo ${1%/*} | tr . /)/${1#*/}/$2/$3
  fi
  unzip -o -q -j $aar jni/arm64-v8a/$4 -d $jni
}

# APP=coredemo or stillfail: the still.fail core, as still.fail's own app runs it (src/host/android_core.c). Into out/android/apk,
# which Gradle packs: ember's prebuilt engine and shell (EMBER: the checkout, as scripts/core.sh has it; `node
# scripts/native.ts path engine|shell android-arm64` there, prebuilt or built by it), libhermes.so from React Native's
# hermes-android (the Hermes the engine is built against: Gradle's cache, else Maven Central), and the core as Hermes
# bytecode (scripts/core.sh hermes; ENTRY picks the core's entry, by default the one with the media module). For the other apps it stays empty.
has_core() { [ $PKG = coredemo ] || [ $PKG = stillfail ]; }

core_parts() {
  local apk=$OUT/apk
  jni=$OUT/apk/jniLibs/arm64-v8a
  rm -rf $apk
  mkdir -p $jni $apk/assets
  has_core || return 0
  EMBER=${EMBER:-$(cd "$TOOLS/.." 2>/dev/null && pwd)/ember-src}
  local engine shell
  engine=$(cd "$EMBER" && node scripts/native.ts path engine android-arm64)
  shell=$(cd "$EMBER" && node scripts/native.ts path shell android-arm64)
  cp -p $engine/libstillfail_hermes.so $engine/libjsi.so $engine/libc++_shared.so $shell/libstillfail_shell.so $jni/
  # Hermes as React Native 0.81.4 has it, and the fbjni it needs (libc++_shared.so is the engine's, the NDK's, which
  # fbjni's AAR carries an older copy of)
  aar_lib com.facebook.react/hermes-android 0.81.4 hermes-android-0.81.4-release.aar libhermes.so
  aar_lib com.facebook.fbjni/fbjni 0.7.0 fbjni-0.7.0.aar libfbjni.so
  if [ -n "${CORE_SCRIPT:-}" ]; then
    # a script in the core's place (listen-test: core/listen-test.js)
    EMBER=$EMBER "$D/core.sh" hermes-script "$CORE_SCRIPT" || { echo "android.sh: $CORE_SCRIPT did not compile" >&2; exit 1; }
  else
    EMBER=$EMBER ENTRY=${ENTRY:-$PWD/core/media-hermes.ts} "$D/core.sh" hermes \
      || { echo "android.sh: no core for the app (scripts/core.sh hermes failed)" >&2; exit 1; }  # with media, as on macOS
  fi
  cp -p out/core/core.hbc $apk/assets/
  echo "core parts: $(cd $jni && for f in *.so; do printf '%s %s, ' $f $(size $f); done)core.hbc $(size $apk/assets/core.hbc)"
}

case "${1:-build}" in
  build)
    T0=$(python3 -c 'import time;print(time.time())')
    sync
    core_parts
    # Gradle keeps what it merged from out/android/apk (the core's .so files, core.hbc) in its intermediates, and a
    # build of an app without the core after one with it would still pack them: built anew when that changes.
    kind=$(has_core && echo core || echo plain)
    if [ "$(cat $OUT/apk-kind 2>/dev/null)" != "$kind" ]; then rm -rf android/app/build; fi
    echo $kind > $OUT/apk-kind
    rm -f $M/_build/native/release/build/$PKG/$PKG.c  # never an old one's
    (cd $M && moon build --target native --release src/$PKG 2>&1) | python3 "$D/errs.py" | grep -v '^errors: 0' || true
    mkdir -p $OUT/obj android/app/src/main/jniLibs/arm64-v8a
    rm -f $OUT/obj/*.o
    $CC $CFLAGS -Dmain=mbui_main -c $M/_build/native/release/build/$PKG/$PKG.c -o $OUT/obj/$PKG.o
    for f in runtime env utf sync_io backtrace; do
      $CC $CFLAGS -c $MOON_HOME/lib/runtime/$f.c -o $OUT/obj/rt_$f.o 2>$OUT/rt_$f.err \
        || { echo "skip runtime/$f.c: $(grep error $OUT/rt_$f.err | head -1)"; rm -f $OUT/obj/rt_$f.o; }
    done
    $CC $CFLAGS -c src/host/android_host.c -o $OUT/obj/android_host.o
    CORE_LIBS=
    if has_core; then
      # mbui/core's queue and the app's engine (src/<app>/android_engine.c, which includes src/sfcore/android_engine.c)
      $CC $CFLAGS -c src/core/core_native.c -o $OUT/obj/core_native.o
      $CC $CFLAGS -c src/$PKG/android_engine.c -o $OUT/obj/android_engine.o
      CORE_LIBS="-L$OUT/apk/jniLibs/arm64-v8a -lstillfail_hermes"
    fi
    $CC -shared -o android/app/src/main/jniLibs/arm64-v8a/libmbui.so $OUT/obj/*.o \
      $CORE_LIBS -lGLESv3 -llog -lm -Wl,--no-undefined
    T1=$(python3 -c 'import time;print(time.time())')
    echo "libmbui.so $(size android/app/src/main/jniLibs/arm64-v8a/libmbui.so) bytes in $(python3 -c "print(round($T1-$T0,2))") s"
    (cd android && ./gradlew --no-daemon -q assembleDebug 2>&1 | grep -v '^$' | tail -20)
    ls -la android/app/build/outputs/apk/debug/*.apk
    ;;
  emu)
    if ! $SDK/emulator/emulator -list-avds | grep -qx $AVD; then
      IMG=$(ls -d $SDK/system-images/android-3*/google_apis*/arm64-v8a 2>/dev/null | sort | tail -1)
      PKG="system-images;$(echo $IMG | sed "s|$SDK/system-images/||; s|/|;|g")"
      echo "creating $AVD from $PKG"
      echo no | $(ls -d $SDK/cmdline-tools/*/bin | tail -1)/avdmanager create avd -n $AVD -k "$PKG" -d pixel_7 >/dev/null
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
    if [ $PKG = photos ]; then photos; fi
    if [ -n "${2:-}" ]; then
      $ADB -s $SERIAL shell am start -n dev.mbui.demo/dev.mbui.MainActivity --es script "$2" ${ENV:+--es env "'$ENV'"} >/dev/null
    else
      $ADB -s $SERIAL shell am start -n dev.mbui.demo/dev.mbui.MainActivity ${BENCH:+--ei bench $BENCH} ${ENV:+--es env "'$ENV'"} >/dev/null
    fi
    ;;
  listen-test)
    # listen.* (CoreHost on Loopback) with core/listen-test.js in the core's place, as scripts/core.sh listen on macOS:
    # it opens a listener on a port of the system's choosing (a second one there, and one off loopback, refused), this
    # sends it a POST from the emulator's shell, the script answers it, then closes it with a listen.next waiting.
    # Builds APP=coredemo with that script (build again without CORE_SCRIPT for the core).
    APP=coredemo CORE_SCRIPT=$PWD/core/listen-test.js "$0" build
    $ADB -s $SERIAL logcat -c
    APP=coredemo ENV="MB_CORE_TRACE=1" "$0" run
    port=
    for i in $(seq 1 30); do
      port=$($ADB -s $SERIAL logcat -d -s mbui:I | sed -n 's/.*core says {"opened":\([0-9]*\).*/\1/p' | head -1)
      [ -n "$port" ] && break
      sleep 1
    done
    [ -n "$port" ] || { echo "FAIL the script opened no listener"; "$0" log 60; exit 1; }
    echo "listening on 127.0.0.1:$port"
    answer=$($ADB -s $SERIAL shell "(printf 'POST /oauth/callback?code=c%%20d&state=s HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 11\r\n\r\nstate=s&x=1'; sleep 3) | nc 127.0.0.1 $port")
    sleep 2
    log=$($ADB -s $SERIAL logcat -d -s mbui:I)
    code=0
    ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; code=1; fi; }
    ok "a second listener on that port refused" 'echo "$log" | grep -q "\"taken\":\"[^\"]*in use"'
    ok "a listener off loopback refused" 'echo "$log" | grep -q "\"outside\":\"[^\"]*not a loopback address"'
    ok "the POST came whole (method, path with its query, Host, body)" 'echo "$log" | grep -q "\"method\":\"POST\",\"path\":\"/oauth/callback?code=c%20d&state=s\".*\"Host\",\"127.0.0.1:$port\".*\"body\":\"state=s&x=1\""'
    ok "the script's answer came back (status, its headers, its body)" 'echo "$answer" | grep -q "^HTTP/1.1 200 OK" && echo "$answer" | grep -q "^X-Test: yes" && echo "$answer" | grep -q "answered /oauth/callback?code=c%20d&state=s"'
    ok "its own Content-Length not passed on (the answer's length is the body's)" '! echo "$answer" | grep -q "^Content-Length: 1\r*$"'
    ok "a listen.next waiting as it closed, and one after, said {end}" 'echo "$log" | grep -q "\"ended\":{\"end\":true},\"after\":{\"end\":true}"'
    ok "it no longer listens" '! $ADB -s $SERIAL shell cat /proc/net/tcp | grep -qi ":$(printf %04X $port) 00000000:0000 0A"'
    echo "$answer" | tr -d '\r' | sed 's/^/  answer: /'
    echo "$log" | grep "core says\|core app call" | sed 's/^/  /' | tail -20
    exit $code
    ;;
  fling-test)
    # Flings the app's first list (the app built already; APP=sffix ENV=MBUI_FIXTURE=long shows a long Home) and
    # records it: out/android/fling/fling.mp4, the app's log of touches and positions frame by frame (MBUI_SCROLL_LOG),
    # and scripts/scrollplot.py's comparison with Compose's fling at the same velocities (fling.txt, fling.png when
    # matplotlib is there: out/venv).
    F=$OUT/fling
    rm -rf $F && mkdir -p $F
    $ADB -s $SERIAL logcat -c
    $ADB -s $SERIAL shell screenrecord --time-limit 40 /sdcard/fling.mp4 &
    REC=$!
    # the flings are Script.java's (--es script fling): swipes at set speeds, as the system delivers a finger's
    ENV="MBUI_SCROLL_LOG=1${ENV:+;$ENV}" "$0" run fling
    for i in $(seq 1 60); do
      $ADB -s $SERIAL logcat -d -s mbui:I | grep -q "script fling: done" && break
      sleep 1
    done
    $ADB -s $SERIAL shell pkill -INT screenrecord || true
    wait $REC || true
    $ADB -s $SERIAL pull /sdcard/fling.mp4 $F/fling.mp4 >/dev/null
    $ADB -s $SERIAL logcat -d -s mbui:I > $F/log.txt
    PY=python3
    [ -x out/venv/bin/python3 ] && PY=out/venv/bin/python3
    $PY "$D/scrollplot.py" $F/log.txt $F/fling.png | tee $F/fling.txt
    ls -la $F
    ;;
  shot)
    mkdir -p $OUT/shots
    $ADB -s $SERIAL exec-out screencap -p > $OUT/shots/$2.png && echo "shot $OUT/shots/$2.png"
    ;;
  log)
    $ADB -s $SERIAL logcat -d -s mbui:I StillFailCore:* AndroidRuntime:E DEBUG:* libc:* | tail -${2:-40}
    ;;
  stop)
    $ADB -s $SERIAL emu kill 2>/dev/null || true
    if [ -f $OUT/http.pid ]; then kill $(cat $OUT/http.pid) 2>/dev/null || true; rm -f $OUT/http.pid; fi
    ;;
  delete)
    $ADB -s $SERIAL emu kill 2>/dev/null || true
    sleep 3
    $(ls -d $SDK/cmdline-tools/*/bin | tail -1)/avdmanager delete avd -n $AVD
    ;;
esac
