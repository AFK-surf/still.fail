#!/bin/bash
# Build the iOS simulator app from the C that `moon build --target native`
# generates, plus the MoonBit runtime and the Objective-C host, then install
# and launch it.  scripts/ios.sh build | run [SCRIPT] | shot NAME
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
OUT=out/ios
APP=$OUT/MBUI.app
BID=dev.mbui.demo
DEV_NAME="mbui-iphone"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
CC="xcrun --sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=17.0 -isysroot $SDK"
CFLAGS="-I$MOON_HOME/include -Isrc/host -Iios/shim -fwrapv -fno-strict-aliasing -Wno-unused-value -O2 -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_SYSTEM"

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
  xcrun simctl bootstatus "$id" -b >/dev/null
  echo "$id"
}

case "${1:-build}" in
  build)
    T0=$(python3 -c 'import time;print(time.time())')
    moon build --target native --release 2>&1 | python3 "$D/errs.py" | grep -v '_main' || true
    C=_build/native/release/build/demo/demo.c
    mkdir -p $OUT/obj $APP
    $CC $CFLAGS -c $C -o $OUT/obj/demo.o
    for f in runtime env utf sync_io backtrace; do
      [ -f $MOON_HOME/lib/runtime/$f.c ] && { $CC $CFLAGS -c $MOON_HOME/lib/runtime/$f.c -o $OUT/obj/rt_$f.o 2>$OUT/rt_$f.err || echo "skip runtime/$f.c: $(head -1 $OUT/rt_$f.err)"; }
    done
    for f in apple_render apple_text ios_app; do
      $CC $CFLAGS -fobjc-arc -c src/host/$f.m -o $OUT/obj/$f.o
    done
    $CC $OUT/obj/*.o -o $APP/mbui -framework UIKit -framework Metal -framework QuartzCore \
      -framework CoreText -framework CoreGraphics -framework ImageIO -framework Foundation -lm
    cp ios/Info.plist $APP/Info.plist
    codesign -s - --force $APP >/dev/null 2>&1
    T1=$(python3 -c 'import time;print(time.time())')
    echo "built $APP in $(python3 -c "print(round($T1-$T0,2))") s; binary $(stat -f %z $APP/mbui) bytes"
    ;;
  run)
    ID=$(device)
    xcrun simctl install "$ID" $APP
    xcrun simctl terminate "$ID" $BID 2>/dev/null || true
    mkdir -p $PWD/$OUT/shots
    SIMCTL_CHILD_MBUI_SCRIPT=${2:-} SIMCTL_CHILD_MBUI_BENCH=${BENCH:-} \
      SIMCTL_CHILD_MBUI_SHOT_DIR=$PWD/$OUT/shots xcrun simctl launch "$ID" $BID
    ;;
  shot)
    ID=$(device)
    mkdir -p $OUT/shots
    xcrun simctl io "$ID" screenshot $OUT/shots/$2.png 2>&1 | tail -2
    ;;
  delete)
    ID=$(device)
    xcrun simctl shutdown "$ID" || true
    xcrun simctl delete "$ID"
    ;;
esac
