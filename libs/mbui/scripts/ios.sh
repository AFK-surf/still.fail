#!/bin/bash
# The iOS app (the simulator's; a device's with MBUI_IOS_SDK=iphoneos): built from the C that `moon build --target native` generates (split and compiled in parallel:
# scripts/mbc), plus the MoonBit runtime and the Objective-C host, then installed and launched on a simulator of our
# own. APP=demo picks the app (src/<APP>).
#   scripts/ios.sh build | run [SCRIPT] | log [N] | stop | shot NAME | device | pid | delete
# ENV="K=V;K2=V2" gives `run` the app's environment variables (simctl's SIMCTL_CHILD_*); its log (stderr: the host's
# log, the drive's lines, the core's) goes to out/ios/app.log (MBUI_IOS_LOG: another file), stdout beside it (.stdout).
#
# An app of a module outside this repository (one whose moon.work names mbui as a member, as scripts/android.sh says):
#   MBUI_APP_MOD     that module's directory (APP is its src/<APP>; out/ and _build/ are its own); default this repo
#   MBUI_IOS_ID      the app's bundle id (default dev.mbui.demo); MBUI_IOS_PLIST its Info.plist (default ios/Info.plist)
#   MBUI_IOS_BUILD   the build's number: its CFBundleVersion (@hostapi.app_version)
#   MBUI_IOS_VERSION explicit marketing version (otherwise legacy 0.1.<build>)
#   MBUI_IOS_SHARE_PLIST  its share extension's Info.plist (src/host/ios_share.m built as PlugIns/Share.appex: what
#     another app shares kept for the app in the app group the two share, group.<its id>, MBUIAppGroup in both
#     Info.plists; both signed with that group, a device's by its packer, whose profile must have it)
#   MBUI_IOS_ASSETS  its asset catalog (an .xcassets: AppIcon its icon, the colours its Info.plist names), compiled into
#     the app (actool), what that adds to the Info.plist with it
#   MBUI_IOS_DEVICE  the simulator's name (default ios-mbui-sf): one of our
#     own, made when missing (the newest iOS runtime, an iPhone Pro); never another's
#   MBUI_IOS_SDK     iphonesimulator (the default: the simulator's app, ad hoc signed) or iphoneos: a device's app, in
#     out/ios-device, its Info.plist saying iPhoneOS, left unsigned (a device's signature is the packer's: its identity,
#     its profile, its entitlements); `build` only
#   MBUI_WASM_THUNKS  builds an app's Wasm shell instead (still.fail's scripts/wasm-app.sh: no C of the app's, its
#     program a .wasm of its own): the host, APP_EXTRA, src/host/wasm_shell.c, those thunks, MBUI_WASM_STUBS and
#     wasmtime (Frameworks/libwasmtime.dylib, built from its source: wasmtime_lib)
#   MBUI_IOS_HOOK    a script sourced here that adds to the build (still.fail's core: its apps/mbui/scripts/ios-core.sh):
#     APP_EXTRA (more C or Objective-C for the app: --extra=FILE ...), APP_LINK (its link flags), APP_ENTITLEMENTS (a
#     plist the app is signed with), and the functions app_libs (before the link: what APP_LINK names made),
#     app_bundle (after the link: into $APPDIR, as frameworks in $APPDIR/Frameworks, signed with it) and app_cmd
#     (commands of its own)
set -eE
# A step that fails says which (a release's TestFlight build stopped with nothing said after its core's libraries,
# 0.1.0 (69), 2026-11-15: set -e leaves a failed plutil, link or copy unsaid)
trap 'echo "ios.sh: line $LINENO: \`$BASH_COMMAND\` failed ($?)" >&2' ERR
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
ROOT=$(cd "$D/.." && pwd)
MOD=$(cd "${MBUI_APP_MOD:-$ROOT}" && pwd)
cd "$MOD"
IOS_SDK=${MBUI_IOS_SDK:-iphonesimulator}
case $IOS_SDK in
  iphonesimulator) OUT=out/ios; MIN=-mios-simulator-version-min=17.0 ;;
  iphoneos) OUT=out/ios-device; MIN=-miphoneos-version-min=17.0 ;;
  *) echo "ios.sh: MBUI_IOS_SDK $IOS_SDK: iphonesimulator or iphoneos" >&2; exit 1 ;;
esac
APPDIR=$OUT/MBUI.app
BID=${MBUI_IOS_ID:-dev.mbui.demo}
DEV_NAME=${MBUI_IOS_DEVICE:-ios-mbui-sf}
PKG=${APP:-demo}
LOG=${MBUI_IOS_LOG:-$PWD/$OUT/app.log}
SDK=$(xcrun --sdk $IOS_SDK --show-sdk-path)
CC="xcrun --sdk $IOS_SDK clang -arch arm64 $MIN -isysroot $SDK"
CFLAGS="-I$MOON_HOME/include -I$ROOT/src/host -I$ROOT/ios/shim -fwrapv -fno-strict-aliasing -Wno-unused-value -O2 -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_SYSTEM"

APP_EXTRA= APP_LINK= APP_ENTITLEMENTS=
[ -z "${MBUI_IOS_HOOK:-}" ] || . "$MBUI_IOS_HOOK"

# wasmtime's C API for the app's Wasm shell (Apache-2.0): no release of it is built for iOS, so its source release
# (fetched once by its checksum) built here by cargo, for the simulator (Cranelift's code, run as it is made) or a
# device (Pulley's: iOS lets no app run code it made, so wasmtime's interpreter), kept in out/ by version and target;
# its headers the macOS release's (the same features). WT_LIB, WT_INCLUDE.
# The toolchain is rustup's WT_RUST (wasmtime 50 asks for Rust 1.97 or later), installed beside the others when missing.
WT_VERSION=50.0.1
WT_SRC_SHA=04c3c71b2fa160236aa8bddf907896dad1e018756366b564fe611643913ed0a5
WT_MAC_SHA=a49327ca596fae51cd92e230265132112bb7896c5a24e4d58cd05b56612e26bb
WT_RUST=${WT_RUST:-1.99.1}
wasmtime_lib() {
  local target features w=$MOD/out/wasmtime-ios
  # (the simulator's with Pulley too: MBUI_WASM_PULLEY=1 runs there what a device runs)
  if [ $IOS_SDK = iphoneos ]; then target=aarch64-apple-ios; else target=aarch64-apple-ios-sim; fi
  features=--features=pulley
  WT_LIB=$w/v$WT_VERSION-$target-pulley/libwasmtime.dylib
  WT_INCLUDE=$w/wasmtime-v$WT_VERSION-aarch64-macos-c-api/include
  mkdir -p $w
  if [ ! -d $WT_INCLUDE ]; then
    curl -fsSL --retry 3 -o $w/mac.tar.xz \
      "https://github.com/bytecodealliance/wasmtime/releases/download/v$WT_VERSION/wasmtime-v$WT_VERSION-aarch64-macos-c-api.tar.xz"
    [ "$(shasum -a 256 $w/mac.tar.xz | awk '{print $1}')" = $WT_MAC_SHA ] || { echo "ios.sh: wasmtime: not the release asked for" >&2; exit 1; }
    tar xf $w/mac.tar.xz -C $w
    rm -f $w/mac.tar.xz
  fi
  [ -f $WT_LIB ] && return 0
  if [ ! -d $w/wasmtime-v$WT_VERSION-src ]; then
    curl -fsSL --retry 3 -o $w/src.tar.gz \
      "https://github.com/bytecodealliance/wasmtime/releases/download/v$WT_VERSION/wasmtime-v$WT_VERSION-src.tar.gz"
    [ "$(shasum -a 256 $w/src.tar.gz | awk '{print $1}')" = $WT_SRC_SHA ] || { echo "ios.sh: wasmtime's source: not the release asked for" >&2; exit 1; }
    tar xzf $w/src.tar.gz -C $w
    rm -f $w/src.tar.gz
  fi
  command -v rustup > /dev/null || export PATH=$HOME/.cargo/bin:$PATH
  rustup run $WT_RUST rustc --version > /dev/null 2>&1 ||
    rustup toolchain install $WT_RUST --profile minimal --target aarch64-apple-ios-sim,aarch64-apple-ios >&2
  rustup target add --toolchain $WT_RUST $target >&2
  (cd $w/wasmtime-v$WT_VERSION-src && CARGO_TARGET_DIR=$w/target \
    cargo +$WT_RUST build --release -p wasmtime-c-api --target $target $features >&2) || exit 1
  mkdir -p $(dirname $WT_LIB)
  cp $w/target/$target/release/libwasmtime.dylib $WT_LIB
  install_name_tool -id @rpath/libwasmtime.dylib $WT_LIB
  # (its source and build, 3.5 GB, gone once the library is kept)
  rm -rf $w/target $w/wasmtime-v$WT_VERSION-src
}

device() {
  local id
  id=$(xcrun simctl list devices -j | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
for rt,ds in d.items():
  for x in ds:
    if x['name']=='$DEV_NAME' and x.get('isAvailable'): print(x['udid']); sys.exit()
")
  if [ -z "$id" ]; then
    local rt=$(xcrun simctl list runtimes -j | python3 -c "import json,sys;r=[x for x in json.load(sys.stdin)['runtimes'] if x['platform']=='iOS' and x['isAvailable']];print(r[-1]['identifier'])")
    local dt=$(xcrun simctl list devicetypes -j | python3 -c "import json,sys;t=[x for x in json.load(sys.stdin)['devicetypes'] if x['name'].startswith('iPhone 1') and 'Pro' in x['name'] and 'Max' not in x['name']];print(t[-1]['identifier'])")
    id=$(xcrun simctl create "$DEV_NAME" "$dt" "$rt")
  fi
  xcrun simctl boot "$id" 2>/dev/null || true
  # until it has booted (`simctl bootstatus`). A fresh simulator's first boot runs its data migration (the address
  # book's plugin can sit idle in it for many minutes on a loaded Mac): it is left to finish by itself, as ending it
  # left SpringBoard launching no app at all (not even Settings). MBUI_IOS_BOOT_WAIT: how long to wait (s, default 40 min).
  local st=$(mktemp -t mbui-bootstatus)
  xcrun simctl bootstatus "$id" >"$st" 2>&1 &
  local pid=$! t0=$(date +%s)
  # (bootstatus' own end: scripts/chk logwait, kqueue's)
  if ! "$D/chk" logwait --pid $pid --deadline ${MBUI_IOS_BOOT_WAIT:-2400}; then
    kill $pid 2>/dev/null
    echo "ios.sh: $DEV_NAME did not boot: $(tail -2 "$st")" >&2
    rm -f "$st"
    return 1
  fi
  wait $pid 2>/dev/null || true
  echo "ios.sh: $DEV_NAME booted in $(($(date +%s) - t0)) s" >&2
  rm -f "$st"
  echo "$id"
}

# the simulator's id when it exists, booted or not (nothing made)
device_id() {
  xcrun simctl list devices -j | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
for rt,ds in d.items():
  for x in ds:
    if x['name']=='$DEV_NAME': print(x['udid']); sys.exit()
"
}

# the app's pid on simulator $1, when it runs (launchd's UIKitApplication:<bundle id>[…] job)
app_pid() {
  xcrun simctl spawn "$1" launchctl list 2>/dev/null | awk -v b="UIKitApplication:$BID[" 'index($3, b) == 1 && $1 != "-" { print $1; exit }'
}

[ $IOS_SDK = iphonesimulator ] || [ "${1:-build}" = build ] || { echo "ios.sh: $1 is the simulator's (MBUI_IOS_SDK=$IOS_SDK)" >&2; exit 1; }
case "${1:-build}" in
  build)
    T0=$(python3 -c 'import time;print(time.time())')
    # the C that moonc generates (scripts/mbc gen: moon's own compile of it for macOS left out), compiled split
    # into units with the runtime and the Objective-C host, all at once (scripts/mbc compile)
    mkdir -p $OUT/obj
    rm -rf $APPDIR && mkdir -p $APPDIR
    LIBS=
    if type app_libs >/dev/null 2>&1; then
      app_libs > $OUT/app-libs.log 2>&1 &
      LIBS=$!
    fi
    R=$MOON_HOME/lib/runtime
    EXTRA=
    for f in apple_render apple_text apple_image apple_listen apple_browser_login apple_passwords apple_views apple_stream ios_app; do
      EXTRA="$EXTRA --extra=$ROOT/src/host/$f.m"
    done
    if [ -n "${MBUI_WASM_THUNKS:-}" ]; then
      # The app's Wasm shell (MBUI_WASM_THUNKS: the shell's side of the app's calls, tools/wasmhost's): the host, the
      # app's C and wasmtime (Frameworks/libwasmtime.dylib), with no C of moonc's; the app, a .wasm of its own, read
      # where MBUI_WASM_APP says (the simulator's: a file of this Mac's, still.fail's scripts/wasm-app.sh) or as
      # app.wasm beside the program
      wasmtime_lib
      : > $OUT/link-flags.txt
      shell_objs $OUT/wobj "$CC" "$CFLAGS -I$WT_INCLUDE" -fobjc-arc ${EXTRA//--extra=/} ${APP_EXTRA//--extra=/} \
        $ROOT/src/host/wasm_shell.c $MBUI_WASM_THUNKS ${MBUI_WASM_STUBS:-} $R/runtime.c > $OUT/objs.txt
      APP_LINK="$APP_LINK $WT_LIB -Wl,-rpath,@executable_path/Frameworks"
    else
      GEN=$("$D/mbc" gen --target-dir $OUT/_build src/$PKG 2>$OUT/moon.log) \
        || { "$D/chk" errs < $OUT/moon.log; grep '^mbc:' $OUT/moon.log; exit 1; }
      "$D/chk" errs < $OUT/moon.log | grep -v '^errors: 0' || true
      "$D/mbc" compile "--cc=$CC" "--cflags=$CFLAGS" --objc-flags=-fobjc-arc --obj=$OUT/obj \
        --link-flags=$OUT/link-flags.txt \
        --optional=$R/runtime.c --optional=$R/env.c --optional=$R/utf.c --optional=$R/sync_io.c --optional=$R/backtrace.c \
        $EXTRA $APP_EXTRA "$GEN" > $OUT/objs.txt
    fi
    if [ -n "$LIBS" ]; then wait $LIBS || { cat $OUT/app-libs.log; exit 1; }; cat $OUT/app-libs.log; fi
    # what the app is signed with: the app's own (APP_ENTITLEMENTS), with a share extension the app group the two
    # share; the simulator reads them from the binary itself (its __TEXT,__entitlements, as Xcode puts them there), a
    # device from the signature
    ENT=$APP_ENTITLEMENTS EXT= SECT=
    if [ -n "${MBUI_IOS_SHARE_PLIST:-}" ]; then
      ENT=$OUT/app.entitlements
      if [ -n "$APP_ENTITLEMENTS" ]; then cp "$APP_ENTITLEMENTS" $ENT; else plutil -create xml1 $ENT; fi
      /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" $ENT > /dev/null 2>&1 || true
      /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups array" \
        -c "Add :com.apple.security.application-groups:0 string group.$BID" $ENT
    fi
    [ -z "$ENT" ] || [ $IOS_SDK != iphonesimulator ] || SECT="-Wl,-sectcreate,__TEXT,__entitlements,$ENT"
    "$D/mbc" link --out=$APPDIR/mbui --stamp=$OUT/mbui.mbc-link -- $CC $(cat $OUT/objs.txt) $(cat $OUT/link-flags.txt) -o $APPDIR/mbui -framework UIKit -framework Metal -framework QuartzCore \
      -framework CoreText -framework CoreGraphics -framework ImageIO -framework Foundation \
      -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework WebKit -framework Photos -framework PhotosUI \
      -framework SafariServices -framework UserNotifications -framework Network -framework UniformTypeIdentifiers -framework GameController \
      -lm $SECT $APP_LINK
    cp ${MBUI_IOS_PLIST:-$ROOT/ios/Info.plist} $APPDIR/Info.plist
    plutil -replace CFBundleIdentifier -string $BID $APPDIR/Info.plist
    # the host's display link asks for up to 120 frames a second (ios_app.m): an iPhone with ProMotion lets an app have
    # more than 60 only where its Info.plist says so
    plutil -replace CADisableMinimumFrameDurationOnPhone -bool YES $APPDIR/Info.plist
    if [ -n "${MBUI_IOS_BUILD:-}" ]; then
      plutil -replace CFBundleVersion -string "$MBUI_IOS_BUILD" $APPDIR/Info.plist
      plutil -replace CFBundleShortVersionString -string "${MBUI_IOS_VERSION:-0.1.$MBUI_IOS_BUILD}" $APPDIR/Info.plist
    fi
    if [ -n "${MBUI_IOS_ASSETS:-}" ]; then
      xcrun actool --compile $APPDIR --platform $IOS_SDK --minimum-deployment-target 17.0 --target-device iphone \
        --app-icon AppIcon --output-partial-info-plist $OUT/assets-info.plist --errors --warnings \
        "$MBUI_IOS_ASSETS" > $OUT/actool.log 2>&1 || { cat $OUT/actool.log; exit 1; }
      /usr/libexec/PlistBuddy -c "Merge $OUT/assets-info.plist" $APPDIR/Info.plist > /dev/null
    fi
    if [ -n "${MBUI_IOS_SHARE_PLIST:-}" ]; then
      # the share extension: its own small program (NSExtensionMain its entry), its Info.plist the app's id and
      # version, the app group both name; both signed with that group (the app's other entitlements with it)
      EXT=$APPDIR/PlugIns/Share.appex
      mkdir -p $EXT
      $CC -fobjc-arc -O2 -fapplication-extension -Wl,-e,_NSExtensionMain -Wl,-application_extension $SECT \
        $ROOT/src/host/ios_share.m -o $EXT/Share -framework Foundation -framework UIKit -framework UniformTypeIdentifiers \
        -framework ImageIO || exit 1
      cp $MBUI_IOS_SHARE_PLIST $EXT/Info.plist
      plutil -replace CFBundleIdentifier -string $BID.share $EXT/Info.plist
      for k in CFBundleVersion CFBundleShortVersionString; do
        plutil -replace $k -string "$(/usr/libexec/PlistBuddy -c "Print :$k" $APPDIR/Info.plist)" $EXT/Info.plist
      done
      for p in $APPDIR/Info.plist $EXT/Info.plist; do plutil -replace MBUIAppGroup -string group.$BID $p; done
    fi
    if [ $IOS_SDK = iphoneos ]; then
      bash "$D/ios-metadata.sh" "$APPDIR/Info.plist" ${EXT:+"$EXT/Info.plist"}
    fi
    if type app_bundle >/dev/null 2>&1; then app_bundle || exit 1; fi
    if [ -n "${MBUI_WASM_THUNKS:-}" ]; then
      mkdir -p $APPDIR/Frameworks
      cp -p $WT_LIB $APPDIR/Frameworks/
    fi
    # what the app carries signed first, then the app (ad hoc: the simulator asks no more; a device's: the packer's)
    if [ $IOS_SDK = iphonesimulator ]; then
      for f in $APPDIR/Frameworks/*; do [ -e "$f" ] && codesign -s - --force "$f" >/dev/null 2>&1; done
      [ -z "${EXT:-}" ] || codesign -s - --force --entitlements $ENT $EXT >/dev/null 2>&1
      codesign -s - --force ${ENT:+--entitlements $ENT} $APPDIR >/dev/null 2>&1
    fi
    T1=$(python3 -c 'import time;print(time.time())')
    echo "built $APPDIR ($BID) in $(python3 -c "print(round($T1-$T0,2))") s; binary $(stat -f %z $APPDIR/mbui) bytes"
    ;;
  run)
    ID=$(device)
    # the last run's app ended, its process gone (kqueue's NOTE_EXIT), before this one is installed over it and
    # launched: SpringBoard still taking the last one down answers a launch "Busy (Application failed preflight
    # checks)" (39467833461)
    old=$(app_pid "$ID")
    [ -z "$old" ] || bash "$D/ios-terminate.sh" "$ID" "$BID"
    [ -z "$old" ] || "$D/chk" logwait --pid "$old" --deadline 60 >/dev/null ||
      { echo "ios.sh: $BID's last run ($old) did not end" >&2; exit 1; }
    xcrun simctl install "$ID" $APPDIR
    mkdir -p $PWD/$OUT/shots "$(dirname "$LOG")"
    # the app's environment: SIMCTL_CHILD_<name> for each of ENV's
    IFS=';' read -ra kv <<< "${ENV:-}"
    for x in "${kv[@]}"; do [ -n "$x" ] && export "SIMCTL_CHILD_$x"; done
    : > "$LOG"
    : > "$LOG.stdout"
    SIMCTL_CHILD_MBUI_SCRIPT=${2:-} SIMCTL_CHILD_MBUI_BENCH=${BENCH:-0} \
      SIMCTL_CHILD_MBUI_SHOT_DIR=${SIMCTL_CHILD_MBUI_SHOT_DIR:-$PWD/$OUT/shots} \
      xcrun simctl launch --terminate-running-process --stdout="$LOG.stdout" --stderr="$LOG" "$ID" $BID \
      >"$LOG.launch" 2>&1 &
    # the app up as it says on its log (ios_app.m's "ios: launched", scripts/chk logwait), then its pid: as the
    # simulator's launchd has it, or as `simctl launch` said it (launchd may not list it yet, or no more: an app that
    # ends at once). `simctl launch` itself can sit on for minutes after the app is up (seen on a loaded Mac), so its
    # end is not waited for, only its line once the app is up
    pid=
    # (or `simctl launch` saying it refused it: said at once, not after the deadline)
    if "$D/chk" logwait --log "$LOG" --line '^ios: launched' --fail-log "$LOG.launch" \
      --fail-line 'An error was encountered|failed to launch' --deadline 120 >/dev/null; then
      pid=$(app_pid "$ID")
      [ -n "$pid" ] || pid=$("$D/chk" logwait --log "$LOG.launch" --line "^$BID: [0-9]+" --deadline 120 | sed "s/^$BID: //")
    fi
    [ -n "$pid" ] || { cat "$LOG.launch" >&2; echo "ios.sh: $BID did not start" >&2; exit 1; }
    echo "$BID: $pid"
    ;;
  pid)
    # the app's pid (a process of this Mac's), when it runs
    app_pid "$(device_id)"
    ;;
  log)
    tail -${2:-40} "$LOG"
    ;;
  device)
    # the simulator's id, made and booted when it is not (for a runner of its own: still.fail's e2e)
    device
    ;;
  stop)
    ID=$(device_id)
    if [ -n "$ID" ] && [ -n "$(app_pid "$ID")" ]; then
      bash "$D/ios-terminate.sh" "$ID" "$BID"
    fi
    ;;
  shot)
    ID=$(device)
    mkdir -p $OUT/shots
    xcrun simctl io "$ID" screenshot "$PWD/$OUT/shots/$2.png" 2>&1 | tail -2
    ;;
  delete)
    ID=$(device_id)
    if [ -n "$ID" ]; then
      xcrun simctl shutdown "$ID" 2>/dev/null || true
      xcrun simctl delete "$ID"
    fi
    ;;
  *)
    if type app_cmd >/dev/null 2>&1; then app_cmd "$@"; else echo "ios.sh: no command $1" >&2; exit 1; fi
    ;;
esac
