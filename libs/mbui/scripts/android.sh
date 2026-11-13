#!/bin/bash
# Android: build libmbui.so from the C that moon generates (split and compiled in parallel: scripts/mbc) plus the
# runtime and src/host/android_host.c, package it with Gradle, and run it on an
# emulator of our own (AVD mbui-avd, port 5580). APP=demo|textdiff picks the app (still.fail's apps: its
# apps/mbui/scripts/android.sh, these scripts on its module);
# ENV="K=V;K2=V2" gives `run` the app's environment variables (MainActivity sets them before the app starts).
#   scripts/android.sh build | emu | run [script] | install | put FILE NAME | shown | uid | shot NAME | record NAME SECONDS [drive] | log | stop | delete
# moon.pkg cannot choose files per OS, so the build runs on a copy of the
# module in out/android/mod, where an app's src/photos/pictures/android.mbt takes pictures_native.mbt's place.
#
# An app of a module outside this repository (one whose moon.work names mbui as a member, its moon.mod importing it):
#   MBUI_APP_MOD       that module's directory (APP is its src/<APP>; out/ and _build/ are its own); default this repo
#   MBUI_ANDROID       the Gradle project that packs it (default android/ here: dev.mbui.demo); MBUI_APP_ID its package
#   MBUI_ANDROID_HOOK  a script sourced here that adds to the build (the still.fail core's: still.fail's
#     apps/mbui/scripts/android-core.sh): APP_EXTRA (more C for libmbui.so: --extra=FILE ...), APP_LINK (its
#     link flags), APP_KIND (what the app packs: a change builds Gradle's outputs anew), and the functions app_libs
#     (alongside the compile: .so files into $jni, before the link), app_assets (alongside: into $apk/assets, before
#     Gradle) and app_cmd (commands of its own)
#   MBUI_BUILD         the build's number (its versionCode, versionName 0.1.<n>; default 1); MBUI_LOG_TAGS more of
#     logcat's tags `log` reads beside mbui's (TAG:LEVEL …)
# VARIANT=release builds the project's release build type (default debug). MBUI_SYMBOLS=<file>: libmbui.so's function
# symbols written there (below, after the link).
# MBUI_WASM_THUNKS=<thunks.c> builds an app's Wasm shell instead (still.fail's scripts/wasm-app.sh: no C of the app's,
# its program a .wasm of its own): the host, the hook's C, src/host/wasm_shell.c, those thunks, MBUI_WASM_STUBS and
# wasmtime; its APK packed again only when what it is made of changed. `put FILE NAME` puts a file in the app's files.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
ROOT=$(cd "$D/.." && pwd)
MOD=$(cd "${MBUI_APP_MOD:-$ROOT}" && pwd)
cd "$MOD"
PROJ=${MBUI_ANDROID:-$ROOT/android}
APP_ID=${MBUI_APP_ID:-dev.mbui.demo}
VARIANT=${VARIANT:-debug}
APK_OUT=$PROJ/app/build/outputs/apk/$VARIANT
APK_FILE=$APK_OUT/app-$VARIANT.apk
# The SDK the machine says, or the usual macOS SDK location (CI: ANDROID_HOME, ANDROID_NDK_LATEST_HOME).
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
NDK=${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-$SDK/ndk/28.2.13676358}}
HOST_TAG=$([ "$(uname)" = Darwin ] && echo darwin-x86_64 || echo linux-x86_64)
TC=$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin
# ABI: the libraries' (default arm64-v8a, a phone's; x86_64 for an x86 machine's emulator: CI's, scripts/render_android.sh)
ABI=${ABI:-arm64-v8a}
case $ABI in
  arm64-v8a) CC="$TC/aarch64-linux-android30-clang" ;;
  x86_64) CC="$TC/x86_64-linux-android30-clang" ;;
  *) echo "android.sh: ABI $ABI: arm64-v8a or x86_64"; exit 1 ;;
esac
export MBUI_ABI=$ABI
ADB=$SDK/platform-tools/adb
AVD=${AVD:-mbui-avd}
PORT=${EMU_PORT:-5580}
SERIAL=emulator-$PORT
OUT=out/android
PKG=${APP:-demo}
M=$OUT/mod
# (a JAVA_HOME already set is kept: CI's, or Homebrew's JDK, which java_home does not list)
[ -z "${JAVA_HOME:-}" ] && [ -x /usr/libexec/java_home ] && export JAVA_HOME=$(/usr/libexec/java_home -v 20 2>/dev/null || /usr/libexec/java_home)
export ANDROID_HOME=$SDK
size() { wc -c < "$1" | tr -d ' '; }
# MoonBit's runtime allocates with mimalloc (mimalloc_obj, below), as moon's own native builds do (the Mac's and
# Windows' apps). It was bionic's scudo only because moon ships mimalloc as a macOS object alone; measured 2026-11-11
# (a 349 KB `chat` message @json.parse'd and let go, the same C, only the allocator differing), scudo took 2.8 times
# as long to decode it and 5 times as long to let it go (a phone: 7.3-15 ms and 2.4-4.9 against 2.6-5.3 and
# 0.7-0.85). What is given up, and why it stays so: mbui's AGENTS.md, The Android app's allocator.
CFLAGS="-I$MOON_HOME/include -I$ROOT/src/host -fPIC -fwrapv -fno-strict-aliasing -Wno-unused-value -O2 -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC"

sync() {
  mkdir -p $M/src
  cp -p moon.mod $M/
  # a workspace's other members where they are (by absolute path: the copy is elsewhere)
  if [ -f moon.work ]; then "$D/mbc" work moon.work $M/moon.work; fi
  # exactly src/: a file gone from it goes from the copy too (then the copy's own files, after)
  if command -v rsync >/dev/null; then rsync -a --delete src/ $M/src/; else rm -rf $M/src && cp -rp src $M/src; fi
  [ ! -f src/photos/pictures/android.mbt ] || cp -p src/photos/pictures/android.mbt $M/src/photos/pictures_native.mbt
  # only moonc's C of the copy is used (scripts/mbc gen): moon compiles and links nothing of it, so the apps'
  # macOS link flags (the core's Apple shell among them) stay as they are
}

# the photos app's pictures: copied into the
# app's files, and one served over http to the emulator's 10.0.2.2 (on 5590:
# the emulator itself takes 5580 and 5581)
photos() {
  P=$OUT/photos
  # the made-up pictures (scripts/test_images.swift --gallery): twelve JPEGs and a big HEIC and JPEG
  gallery_pictures
  mkdir -p $P
  cp -p out/pictures/[0-9]*.jpg out/pictures/big.heic out/pictures/big.jpg $P/
  cp -p $ROOT/test/images/*.jpg $P/
  $ADB -s $SERIAL shell run-as $APP_ID mkdir -p files/photos
  for f in $P/*.jpg $P/*.heic; do
    $ADB -s $SERIAL exec-in "run-as $APP_ID sh -c 'cat > files/photos/$(basename $f)'" < $f
  done
  if ! curl -s -o /dev/null http://127.0.0.1:5590/; then
    nohup python3 -m http.server 5590 --bind 127.0.0.1 -d $P >$OUT/http.log 2>&1 &
    echo $! > $OUT/http.pid
  fi
}

# What an app adds (MBUI_ANDROID_HOOK: still.fail's the core's), into out/android/apk, which
# Gradle packs (its project's sourceSets): .so files in apk/jniLibs/arm64-v8a ($jni), assets in apk/assets.
APP_EXTRA= APP_LINK= APP_KIND=plain
apk=$OUT/apk
jni=$OUT/apk/jniLibs/$ABI
[ -z "${MBUI_ANDROID_HOOK:-}" ] || . "$MBUI_ANDROID_HOOK"

# wasmtime's C API for the ABI (Apache-2.0, a release of its own, fetched once by its checksum): its headers ($WT/include)
# and libwasmtime.so into $jni
WT_VERSION=50.0.1
wasmtime_lib() {
  local arch sha
  case $ABI in
    arm64-v8a) arch=aarch64 sha=611b6cd99939767684f48bd4cf3db559db4fde4992c949057be1e815ec2a9e70 ;;
    x86_64) arch=x86_64 sha=637f68d80b613f476a7d367d81333fba494db3696d9258a5f6647b257101fbea ;;
  esac
  WT=$OUT/wasmtime-v$WT_VERSION-$arch-android-c-api
  if [ ! -f $WT/lib/libwasmtime.so ]; then
    curl -fsSL --retry 3 -o $OUT/wasmtime.tar.xz \
      "https://github.com/bytecodealliance/wasmtime/releases/download/v$WT_VERSION/wasmtime-v$WT_VERSION-$arch-android-c-api.tar.xz"
    [ "$(shasum -a 256 $OUT/wasmtime.tar.xz | awk '{print $1}')" = "$sha" ] \
      || { echo "android.sh: wasmtime: not the release asked for" >&2; exit 1; }
    tar xf $OUT/wasmtime.tar.xz -C $OUT
    rm -f $OUT/wasmtime.tar.xz
  fi
  cp -p $WT/lib/libwasmtime.so $jni/
}

# mimalloc (MIT), the version in moon's prebuilt libmoonbitrun.o, so Android runs the Mac's and Windows' allocator: its
# source release fetched once by its checksum, its one-file build (src/static.c) compiled for the ABI as its CMake
# builds the static library in release, by way of src/host/mimalloc_android.c (libc's calls in its raw system calls'
# place: Android's seccomp filter killed x86_64's raw access(2)). Without its override of malloc (MI_MALLOC_OVERRIDE
# unset): only MoonBit's runtime calls it (mi_malloc, mi_free; mi_register_deferred_free only were
# MOONBIT_TRIAL_DELETION on), and the JVM, Skia, Hermes and the Rust shell in the same process keep the system's; its
# symbols hidden, so libmbui.so exports none of them. Prints its object.
MI_VERSION=2.1.7
mimalloc_obj() {
  local mi=$OUT/mimalloc-$MI_VERSION tmp
  if [ ! -f $mi/src/static.c ]; then
    tmp=$OUT/mimalloc-$$
    rm -rf $tmp && mkdir -p $tmp
    curl -fsSL --retry 3 -o $tmp/mimalloc.tar.gz \
      "https://github.com/microsoft/mimalloc/archive/refs/tags/v$MI_VERSION.tar.gz"
    [ "$(shasum -a 256 $tmp/mimalloc.tar.gz | awk '{print $1}')" = 0eed39319f139afde8515010ff59baf24de9e47ea316a315398e8027d198202d ] \
      || { echo "android.sh: mimalloc: not the release asked for" >&2; exit 1; }
    tar xzf $tmp/mimalloc.tar.gz -C $tmp
    rm -rf $mi && mv $tmp/mimalloc-$MI_VERSION $mi && rm -rf $tmp
  fi
  shell_objs $OUT/mimalloc-$ABI "$CC" "-O3 -fPIC -DNDEBUG -DMI_SECURE=0 -fvisibility=hidden -I$mi/include -I$mi/src" "" \
    $ROOT/src/host/mimalloc_android.c
}

now() { python3 -c 'import time;print(time.time())'; }
secs() { python3 -c "print(f'{$2-$1:.1f}')"; }

case "${1:-build}" in
  build)
    # The C that moonc generates, without moon's compile of it for this machine (scripts/mbc gen: 2 s where moon's
    # own build took a minute), compiled split into units, all at once, with the runtime, the host and the core's C
    # (scripts/mbc compile: an object whose inputs did not change is kept); the core's parts alongside; then Gradle
    # (its daemon and build cache: android/gradle.properties). MBC_SPLIT=0 compiles the C whole, as one unit.
    T0=$(now)
    sync
    rm -rf "${apk:?}"
    mkdir -p $jni $apk/assets
    LIBS= HBC=
    # (mimalloc beside the rest: its object linked with the others)
    mimalloc_obj > $OUT/mimalloc-obj.txt 2> $OUT/mimalloc.log &
    MIO=$!
    if type app_libs >/dev/null 2>&1; then
      app_libs > $OUT/app-libs.log 2>&1 &
      LIBS=$!
    fi
    if type app_assets >/dev/null 2>&1; then
      app_assets > $OUT/app-assets.log 2>&1 &
      HBC=$!
    fi
    # The APK's dex (javac, then R8: a minute when the Java changed, 62 s of main's 192 s android job, 40126602560)
    # needs nothing built here: begun now, beside moonc and cc, kept by what it is made of (scripts/apk); the APK's
    # build at the end finds it kept
    DEX=
    # (a Wasm shell's APK is mostly the one before it: packed only when what it is made of changed, below)
    if [ -f $PROJ/apk.json ] && [ -z "${MBUI_WASM_THUNKS:-}" ]; then
      n=${MBUI_BUILD:-1}
      "$D/apk" build $PROJ/apk.json --variant $VARIANT --version-code $n --version-name 0.1.$n --abi $ABI \
        --out $APK_FILE --dex-only > $OUT/apk-dex.log 2>&1 &
      DEX=$!
    fi
    # Gradle keeps what it merged from out/android/apk (the core's .so files, core.hbc) in its intermediates, and a
    # build of an app without the core after one with it would still pack them: built anew when that changes.
    if [ "$(cat $OUT/apk-kind 2>/dev/null)" != "$APP_KIND" ]; then rm -rf "${PROJ:?}/app/build"; fi
    echo $APP_KIND > $OUT/apk-kind
    EXTRA="--extra=$ROOT/src/host/android_host.c $APP_EXTRA"
    if [ -n "${MBUI_WASM_THUNKS:-}" ]; then
      # The app's Wasm shell (MBUI_WASM_THUNKS: the shell's side of the app's calls, tools/wasmhost's): the host, the
      # app's C and wasmtime, with no C of moonc's; the app, a .wasm of its own, put beside it as it runs
      # (still.fail's scripts/wasm-app.sh)
      wasmtime_lib
      EXTRA="$EXTRA --extra=$ROOT/src/host/wasm_shell.c --extra=$MBUI_WASM_THUNKS"
      # (and the native stubs of the app's packages the thunks call: MBUI_WASM_STUBS, which moonc's C would bring)
      for f in ${MBUI_WASM_STUBS:-}; do EXTRA="$EXTRA --extra=$f"; done
      CFLAGS="$CFLAGS -I$WT/include"
      APP_LINK="$APP_LINK -L$jni -lwasmtime"
    else
      GEN=$("$D/mbc" gen --dir $M src/$PKG 2>$OUT/moon.log) \
        || { "$D/chk" errs < $OUT/moon.log; grep '^mbc:' $OUT/moon.log; exit 1; }
      "$D/chk" errs < $OUT/moon.log | grep -v '^errors: 0' || true
    fi
    T1=$(now)
    SO=$PROJ/app/src/main/jniLibs/$ABI/libmbui.so
    mkdir -p $OUT/obj $(dirname $SO)
    R=$MOON_HOME/lib/runtime
    if [ -n "${MBUI_WASM_THUNKS:-}" ]; then
      : > $OUT/link-flags.txt
      shell_objs $OUT/wobj "$CC" "$CFLAGS" "" ${EXTRA//--extra=/} $R/runtime.c > $OUT/objs.txt
    else
      "$D/mbc" compile "--cc=$CC" "--cflags=$CFLAGS" --gen-flags=-Dmain=mbui_main --obj=$OUT/obj \
        --link-flags=$OUT/link-flags.txt \
        --optional=$R/runtime.c --optional=$R/env.c --optional=$R/utf.c --optional=$R/sync_io.c --optional=$R/backtrace.c \
        $EXTRA "$GEN" > $OUT/objs.txt
    fi
    wait $MIO || { cat $OUT/mimalloc.log; exit 1; }
    cat $OUT/mimalloc-obj.txt >> $OUT/objs.txt
    T2=$(now)
    if [ -n "$LIBS" ]; then wait $LIBS || { cat $OUT/app-libs.log; exit 1; }; cat $OUT/app-libs.log; fi
    T3=$(now)
    # (ThinLTO's backends run here when MBC_LTO asks for them: scripts/mbc's link flags), unless the same command made libmbui.so of the same
    # objects and the core's .so files already (scripts/mbc link: by content)
    "$D/mbc" link --out=$SO --dep=$jni -- $CC -shared -o $SO $(cat $OUT/objs.txt) $(cat $OUT/link-flags.txt) \
      $APP_LINK -lGLESv3 -llog -lz -lm -Wl,--no-undefined
    T4=$(now)
    # MBUI_SYMBOLS=<file>: the library's function symbols written there, `<address> <name>` a line, xz'd (still.fail's
    # release keeps them to name the frames of its crash reports: its scripts/crash-symbols.ts). Read from the library
    # as linked, before the APK's packing strips it (scripts/apk), its addresses the same; written whether or not the
    # link above was skipped. Never the build's failure: a warning, and none.
    if [ -n "${MBUI_SYMBOLS:-}" ]; then
      rm -f "$MBUI_SYMBOLS"
      if mkdir -p "$(dirname "$MBUI_SYMBOLS")" && "$TC/llvm-nm" -n --defined-only $SO > $OUT/symbols.nm \
        && awk '$2 ~ /^[tTwW]$/ { print $1, $3 }' $OUT/symbols.nm | xz -6 > "$MBUI_SYMBOLS.part" \
        && [ -s "$MBUI_SYMBOLS.part" ] && mv "$MBUI_SYMBOLS.part" "$MBUI_SYMBOLS"; then
        echo "android.sh: symbols $(size "$MBUI_SYMBOLS") bytes ($(awk '$2 ~ /^[tTwW]$/' $OUT/symbols.nm | wc -l | tr -d ' ') functions) in $(secs $T4 $(now)) s: $MBUI_SYMBOLS"
      else
        rm -f "$MBUI_SYMBOLS.part"
        echo "android.sh: warning: no symbols written to $MBUI_SYMBOLS" >&2
      fi
      rm -f $OUT/symbols.nm
    fi
    echo "libmbui.so $(size $SO) bytes in $(secs $T0 $T4) s"
    if [ -n "$HBC" ]; then wait $HBC || { cat $OUT/app-assets.log; exit 1; }; cat $OUT/app-assets.log; fi
    if [ -n "$DEX" ]; then wait $DEX || { cat $OUT/apk-dex.log; exit 1; }; cat $OUT/apk-dex.log; fi
    T5=$(now)
    # A Wasm shell's APK as it was, when all it is made of is (apk.json's Java, resources, assets and libraries, by
    # content: libmbui.so, linked again only for a change of its own, is the same file): packing it again takes 30 s
    KEY=
    if [ -n "${MBUI_WASM_THUNKS:-}" ] && [ -f $PROJ/apk.json ]; then
      KEY=$( (echo "$VARIANT $ABI ${MBUI_BUILD:-1}"
        find $PROJ/apk.json $PROJ/apk.lock $PROJ/app/src $PROJ/app/proguard-rules.pro $ROOT/android/app/src $apk -type f \
          -print0 | LC_ALL=C sort -z | xargs -0 shasum) | shasum | cut -c1-40)
    fi
    if [ -n "$KEY" ] && [ -f $APK_FILE ] && [ "$(cat $OUT/apk.key 2>/dev/null)" = "$KEY" ]; then
      echo "android.sh: the APK as it was (what it is made of unchanged)"
    elif [ -f $PROJ/apk.json ]; then
      # (its failure is the build's: an APK of an earlier build must not pass for this one's)
      rm -f "${APK_OUT:?}"/*.apk $OUT/apk.key
      # without Gradle (scripts/apk, tools/apk: R8's dex kept by what it is made of, the build's number in the manifest
      # alone); its number MBUI_BUILD
      mkdir -p $APK_OUT
      n=${MBUI_BUILD:-1}
      "$D/apk" build $PROJ/apk.json --variant $VARIANT --version-code $n --version-name 0.1.$n --abi $ABI \
        --out $APK_FILE
      [ -z "$KEY" ] || echo "$KEY" > $OUT/apk.key
    # (on CI the tasks that ran, by name, the log's times between them what each took; quiet elsewhere)
    elif [ -n "${GITHUB_ACTIONS:-}" ]; then
      rm -f "${APK_OUT:?}"/*.apk
      (cd $PROJ && set -o pipefail && ./gradlew --console=plain assemble$(echo ${VARIANT:0:1} | tr a-z A-Z)${VARIANT:1} 2>&1 |
        { grep -E '^> Task|^BUILD|actionable|^FAILURE|What went wrong|^e: |error:' | grep -vE 'UP-TO-DATE$|NO-SOURCE$|SKIPPED$' || true; })
    else
      rm -f "${APK_OUT:?}"/*.apk
      (cd $PROJ && set -o pipefail && ./gradlew -q assemble$(echo ${VARIANT:0:1} | tr a-z A-Z)${VARIANT:1} 2>&1 | { grep -v '^$' || true; } | tail -20)
    fi
    T6=$(now)
    ls -la $APK_OUT/*.apk
    echo "android.sh: APP=$PKG APK in $(secs $T0 $T6) s: moonc $(secs $T0 $T1) s, cc $(secs $T1 $T2) s," \
      "the app's .so wait $(secs $T2 $T3) s, link $(secs $T3 $T4) s, its assets wait $(secs $T4 $T5) s, packed $(secs $T5 $T6) s"
    ;;
  emu)
    if ! $SDK/emulator/emulator -list-avds | grep -qx $AVD; then
      IMG=$(ls -d $SDK/system-images/android-3*/google_apis*/arm64-v8a 2>/dev/null | sort | tail -1)
      PKG="system-images;$(echo $IMG | sed "s|$SDK/system-images/||; s|/|;|g")"
      echo "creating $AVD from $PKG"
      echo no | $(ls -d $SDK/cmdline-tools/*/bin | tail -1)/avdmanager create avd -n $AVD -k "$PKG" -d pixel_7 >/dev/null
    fi
    # (EMU_FLAGS: the emulator's own besides, still.fail's idle memory's: its data wiped, a small data partition)
    if ! $ADB devices | grep -q "^$SERIAL"; then
      mkdir -p $OUT
      nohup $SDK/emulator/emulator -avd $AVD -port $PORT -no-window -no-audio -no-boot-anim \
        -gpu swiftshader_indirect -no-snapshot ${EMU_FLAGS:-} >$OUT/emu.log 2>&1 &
    fi
    $ADB -s $SERIAL wait-for-device
    # booted: init's own word as the system sets sys.boot_completed (its actions for it, on the log from the boot's
    # start: `logcat -m 1` reads what is there, then waits for it), unless it was set already
    if [ "$($ADB -s $SERIAL shell getprop sys.boot_completed | tr -d '\r')" != 1 ]; then
      $ADB -s $SERIAL logcat -b all -v brief -m 1 -e 'processing action \(sys\.boot_completed=1' | grep -q boot_completed \
        || { echo "android.sh: no boot on the log of $SERIAL" >&2; exit 1; }
    fi
    echo "emulator ready"
    ;;
  run)
    # (INSTALL=0: what is installed is run as it is: still.fail's scripts/wasm-app.sh, which installs the shell's APK
    # only when it changed)
    [ "${INSTALL:-1}" = 0 ] || $ADB -s $SERIAL install -r ${APK:-$APK_FILE} >/dev/null
    $ADB -s $SERIAL shell am force-stop $APP_ID
    # (a phone takes an intent's script and env only in a debug build the shell opened them in: MainActivity.testHooks)
    case "$($ADB -s $SERIAL shell getprop ro.hardware | tr -d '\r')" in
      ranchu | goldfish) ;;
      *) [ "$($ADB -s $SERIAL shell getprop debug.mbui.hooks | tr -d '\r')" = 1 ] \
           || echo "android.sh: $SERIAL is a phone: its app takes no script or env (adb shell setprop debug.mbui.hooks 1 opens them in a debug build)" >&2 ;;
    esac
    if [ $PKG = photos ]; then photos; fi
    if [ -n "${2:-}" ]; then
      $ADB -s $SERIAL shell am start -n $APP_ID/dev.mbui.MainActivity --es script "$2" ${ENV:+--es env "'$ENV'"} >/dev/null
    else
      $ADB -s $SERIAL shell am start -n $APP_ID/dev.mbui.MainActivity ${BENCH:+--ei bench $BENCH} ${SHOT_AT:+--ei shot_at $SHOT_AT} ${ENV:+--es env "'$ENV'"} >/dev/null
    fi
    ;;
  install)
    $ADB -s $SERIAL install -r ${APK:-$APK_FILE} >/dev/null
    ;;
  put)
    # `put FILE NAME`: FILE as NAME in the app's own files (run-as: a debuggable build's), by way of the shell's
    # /data/local/tmp (a pipe into run-as, exec-in, came back with a 18 MB file a third short)
    $ADB -s $SERIAL push "$2" /data/local/tmp/mbui-put-$3 > /dev/null
    $ADB -s $SERIAL shell "run-as $APP_ID sh -c 'mkdir -p files && cp /data/local/tmp/mbui-put-$3 files/$3.part && mv files/$3.part files/$3'; rm -f /data/local/tmp/mbui-put-$3"
    [ "$($ADB -s $SERIAL shell run-as $APP_ID stat -c %s files/$3 | tr -d '\r')" = "$(size "$2")" ] \
      || { echo "android.sh: $3 is not whole in $APP_ID's files" >&2; exit 1; }
    ;;
  fling-test)
    # Flings the app's first list (the app built already) and
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
    # the script's own named end (Script.java), or the app's crash, as logcat has it (cleared above: this run's)
    $ADB -s $SERIAL logcat -v brief -m 1 --uid=$("$0" uid) -e "script fling: done|FATAL EXCEPTION|Fatal signal" >/dev/null
    $ADB -s $SERIAL shell pkill -INT screenrecord || true
    wait $REC || true
    $ADB -s $SERIAL pull /sdcard/fling.mp4 $F/fling.mp4 >/dev/null
    $ADB -s $SERIAL logcat -d -s mbui:I > $F/log.txt
    PY=python3
    [ -x out/venv/bin/python3 ] && PY=out/venv/bin/python3
    $PY "$D/scrollplot.py" $F/log.txt $F/fling.png | tee $F/fling.txt
    ls -la $F
    ;;
  record)
    # A motion recorded on the emulator (the app built already): `record NAME SECONDS [drive script]` starts the app
    # with ENV and MBUI_MOTION_LOG=1 (and scripts/motion/<drive script>.drive as MBUI_DRIVE_B64), records the screen
    # meanwhile: out/android/rec/NAME.mp4, NAME.log (the app's log: `MOTION …` lines for scripts/motionplot.py).
    R=$OUT/rec
    mkdir -p $R
    NAME=${2:-motion}
    SECS=${3:-10}
    DRV=""
    # (the app module's scripts/motion/NAME.drive)
    [ -n "${4:-}" ] && DRV="MBUI_DRIVE_B64=$(base64 < scripts/motion/$4.drive | tr -d '\n');"
    # (recorded into the shell's own /data/local/tmp: there from boot, not the shared storage that comes later)
    $ADB -s $SERIAL logcat -c
    $ADB -s $SERIAL shell screenrecord --verbose --time-limit $SECS /data/local/tmp/$NAME.mp4 > $R/$NAME.rec.txt 2>&1 &
    REC=$!
    # the app started once the recorder is (its words as it begins: the display it records set up), or it ended
    "$D/chk" logwait --log $R/$NAME.rec.txt --line '^Content area is' --pid $REC --deadline 60 >/dev/null \
      || { cat $R/$NAME.rec.txt; echo "android.sh: the recorder did not start" >&2; exit 1; }
    ENV="${DRV}MBUI_MOTION_LOG=1${ENV:+;$ENV}" "$0" run
    # (the file whole once screenrecord has ended: the shell's end is its)
    wait $REC || true
    $ADB -s $SERIAL pull /data/local/tmp/$NAME.mp4 $R/$NAME.mp4 >/dev/null
    $ADB -s $SERIAL shell rm -f /data/local/tmp/$NAME.mp4
    $ADB -s $SERIAL logcat -d -s mbui:I > $R/$NAME.log
    echo "RECORDED $R/$NAME.mp4 ($(grep -c MOTION $R/$NAME.log) moving frames logged)"
    ;;
  shown)
    # Until the app's own window is what the screen shows: it has the focus, and the system's starting window (its
    # splash, "Splash Screen <package>", or a snapshot's) is gone. A frame on the app's window, focused (MBView's
    # "SHOT n t"), can still be under the splash as the system fades it out; a picture taken then is the splash's.
    # (the whole dump: its windows, and each display's focus, mCurrentFocus)
    for n in $(seq 600); do
      w=$($ADB -s $SERIAL shell dumpsys window | tr -d '\r')
      if echo "$w" | grep -q "mCurrentFocus=.* $APP_ID/" && ! echo "$w" | grep -qE "Window\{[0-9a-f]+ u[0-9]+ (Splash Screen $APP_ID|SnapshotStartingWindow)"; then
        echo "android.sh: $APP_ID's window shown ($n looks)"
        exit 0
      fi
    done
    echo "android.sh: $APP_ID's window not the one shown ($SERIAL)" >&2
    echo "$w" | grep -iE "focus|splash|starting" | head -20 >&2
    exit 1
    ;;
  uid)
    # The app's uid (installed): what `logcat --uid` keeps to, so another app's crash on the emulator (its FATAL
    # EXCEPTION, its Fatal signal) is not taken for this one's.
    $ADB -s $SERIAL shell pm list packages -U $APP_ID | tr -d '\r' | sed -n "s/^package:$APP_ID uid:\([0-9]*\).*/\1/p"
    ;;
  shot)
    mkdir -p $OUT/shots
    $ADB -s $SERIAL exec-out screencap -p > $OUT/shots/$2.png && echo "shot $OUT/shots/$2.png"
    ;;
  log)
    $ADB -s $SERIAL logcat -d -s mbui:I ${MBUI_LOG_TAGS:-} AndroidRuntime:E DEBUG:* libc:* | tail -${2:-40}
    ;;
  stop)
    $ADB -s $SERIAL emu kill 2>/dev/null || true
    if [ -f $OUT/http.pid ]; then kill $(cat $OUT/http.pid) 2>/dev/null || true; rm -f $OUT/http.pid; fi
    ;;
  delete)
    # the emulator's processes (its qemu) ended before its files go: their end, not a time (scripts/chk logwait)
    EPIDS=$(pgrep -f -- "-avd $AVD( |$)" || true)
    $ADB -s $SERIAL emu kill 2>/dev/null || true
    for p in $EPIDS; do "$D/chk" logwait --pid $p --deadline 120; done
    $(ls -d $SDK/cmdline-tools/*/bin | tail -1)/avdmanager delete avd -n $AVD
    ;;
  *)
    if type app_cmd >/dev/null 2>&1; then app_cmd "$@"; else echo "android.sh: no command $1" >&2; exit 1; fi
    ;;
esac
