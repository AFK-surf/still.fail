#!/bin/bash
# Screenshots of the demo on every platform, compared with goldens/.
#   scripts/shots.sh [mac web ios android | windows | kit]   UPDATE=1 accepts them as goldens
# `kit` is the components' gallery (APP=kitdemo, docs/components.md) on macOS, a page a shot (KIT_PAGES, all by
# default), the light theme beside the dark one: goldens/mac-kit-<page>.png.
# Writes out/shots/<name>.png and, where a golden exists, out/shots/<name>-review.png (golden | new | differences).
# (still.fail's screens in mbui, and their goldens, are in still.fail's repository: apps/mbui/scripts/shots.sh.)
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
mkdir -p out/shots goldens
PLATFORMS=${*:-mac web ios android}
if [ ! -d out/node/node_modules/pixelmatch ]; then
  (cd out/node 2>/dev/null || { mkdir -p out/node && cd out/node && npm init -y >/dev/null; }; npm i pngjs pixelmatch playwright >/dev/null 2>&1)
fi
fail=0
for p in $PLATFORMS; do
  names=$p
  case $p in
    mac)
      MODE=release bash scripts/mac.sh build >/dev/null
      rm -rf out/shot-mac; mkdir -p out/shot-mac
      MBUI_BENCH=-1 MBUI_SCRIPT=shot MBUI_SHOT_DIR=$PWD/out/shot-mac ./_build/native/release/build/demo/demo.exe >/dev/null
      cp out/shot-mac/main.png out/shots/mac.png ;;
    kit)  # not part of the default set
      APP=kitdemo MODE=release bash scripts/mac.sh build >/dev/null
      rm -rf out/shot-kit; mkdir -p out/shot-kit
      names=""
      for s in ${KIT_PAGES:-foundation controls overlays menus disclosure}; do
        MBUI_BENCH=-1 MBUI_SCREEN=$s MBUI_WIN=960x720 MBUI_SCRIPT=shot MBUI_SHOT_NAME=$s MBUI_SHOT_DIR=$PWD/out/shot-kit \
          ./_build/native/release/build/kitdemo/kitdemo.exe >/dev/null
        cp out/shot-kit/$s.png out/shots/mac-kit-$s.png
        names="$names mac-kit-$s"
      done ;;
    windows)  # on Windows (Git Bash), not part of the default set
      MODE=release bash scripts/win.sh build >/dev/null
      MODE=release bash scripts/win.sh shot >/dev/null
      cp out/shot-win/main.png out/shots/windows.png ;;
    web)
      bash scripts/web.sh build >/dev/null
      # the demo's first screen at its declared moment: nothing moves as it starts (no motion said before an input), and
      # its list's rows are measured by the frames its first moment asks for (Tester::draw: three at most), here 1/60 s
      # apart on the run's own clock (web/host.js shot_at): the picture is of the frame at 100 ms
      NODE_PATH=$PWD/out/node/node_modules node scripts/web-shot.mjs out/shots/web.png 100 ;;
    ios)
      bash scripts/ios.sh build >/dev/null
      rm -rf out/ios/shots
      BENCH=-1 bash scripts/ios.sh run shot >/dev/null
      # its picture written, as the app says on its log once it is (ios_app.m's "SHOT <path> ok"; scripts/ios.sh's log)
      python3 scripts/logwait.py --log "${MBUI_IOS_LOG:-$PWD/out/ios/app.log}" --line '^SHOT .*/main\.png (ok|failed)$' --deadline 120 \
        | grep -q ' ok$' || { echo "ios: no picture"; fail=1; continue; }
      cp out/ios/shots/main.png out/shots/ios.png ;;
    android)
      bash scripts/android.sh build >/dev/null
      bash scripts/android.sh emu >/dev/null
      A=$HOME/Library/Android/sdk/platform-tools/adb
      $A -s emulator-${EMU_PORT:-5580} shell settings put global sysui_demo_allowed 1
      $A -s emulator-${EMU_PORT:-5580} shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null
      $A -s emulator-${EMU_PORT:-5580} shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 1200 >/dev/null
      $A -s emulator-${EMU_PORT:-5580} shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false >/dev/null
      # the demo's first screen at its declared moment (as the browser's, above): the app's frames on its own clock
      # (MBView's shot_at) to the frame at 100 ms, which it says once it is on the screen ("SHOT n t")
      $A -s emulator-${EMU_PORT:-5580} logcat -c
      SHOT_AT=100 BENCH=-1 bash scripts/android.sh run
      $A -s emulator-${EMU_PORT:-5580} logcat -v raw -m 1 -e "SHOT [0-9]+ [0-9]|FATAL EXCEPTION|Fatal signal" \
        | grep -q "SHOT [0-9]" || { echo "android: no picture"; fail=1; continue; }
      $A -s emulator-${EMU_PORT:-5580} exec-out screencap -p > out/shots/android.png ;;
  esac
  for p in $names; do
    if [ "${UPDATE:-}" = 1 ]; then
      cp out/shots/$p.png goldens/$p.png && echo "$p: golden updated"
    elif [ -f goldens/$p.png ]; then
      NODE_PATH=$PWD/out/node/node_modules node scripts/imgdiff.mjs goldens/$p.png out/shots/$p.png out/shots/$p-review.png || fail=1
    else
      echo "$p: no golden yet (UPDATE=1 to accept)"
    fi
  done
done
exit $fail
