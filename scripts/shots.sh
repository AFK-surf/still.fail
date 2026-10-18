#!/bin/bash
# Screenshots of the demo on every platform, compared with goldens/.
#   scripts/shots.sh [mac kit web web-kit ios android | windows]   UPDATE=1 accepts them as goldens
# Writes out/shots/<name>.png and, where a golden exists,
# out/shots/<name>-review.png (golden | new | differences). `kit` (macOS) and
# `web-kit` are the demo's kit screen (MBUI_SCREEN=kit, a phone's window: rich
# text, Markdown, pages): kit gives mac-kit (its first page) and mac-kit-swipe
# (the next page pushed, then swiped halfway back from the left edge). `home` (macOS) and `web-home` are still.fail's
# Home over made-up chats (APP=sffix, src/sfapp/fixture.mbt) in a phone's window: home gives mac-home (the list),
# mac-home-sheet (the workspaces' sheet) and mac-home-swipe (a chat pushed, swiped halfway back). `chat` (macOS) and
# `web-chat` are a made-up chat open over it (MBUI_FIXTURE=chat, src/sfapp/chat_fixture.mbt): chat gives mac-chat (at
# its end), mac-chat-up (scrolled up: the way to the newest over it) and mac-chat-loading (being read).
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
mkdir -p out/shots goldens
PLATFORMS=${*:-mac kit home chat web web-kit web-home web-chat ios android}
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
    kit)
      MODE=release bash scripts/mac.sh build >/dev/null
      rm -rf out/shot-kit; mkdir -p out/shot-kit
      MBUI_BENCH=-1 MBUI_SCREEN=kit MBUI_WIN=390x844 MBUI_SCRIPT=kit MBUI_SHOT_DIR=$PWD/out/shot-kit ./_build/native/release/build/demo/demo.exe >/dev/null
      cp out/shot-kit/kit-1-root.png out/shots/mac-kit.png
      cp out/shot-kit/kit-3-swipe.png out/shots/mac-kit-swipe.png
      names="mac-kit mac-kit-swipe" ;;
    home)
      APP=sffix MODE=release bash scripts/mac.sh build >/dev/null
      rm -rf out/shot-home; mkdir -p out/shot-home
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_SCRIPT=home MBUI_SHOT_DIR=$PWD/out/shot-home ./_build/native/release/build/sffix/sffix.exe >/dev/null
      cp out/shot-home/home-1.png out/shots/mac-home.png
      cp out/shot-home/home-2-workspaces.png out/shots/mac-home-sheet.png
      cp out/shot-home/home-4-swipe.png out/shots/mac-home-swipe.png
      names="mac-home mac-home-sheet mac-home-swipe" ;;
    chat)
      APP=sffix MODE=release bash scripts/mac.sh build >/dev/null
      rm -rf out/shot-chat; mkdir -p out/shot-chat
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat MBUI_SCRIPT=chat MBUI_SHOT_DIR=$PWD/out/shot-chat ./_build/native/release/build/sffix/sffix.exe >/dev/null
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat-loading MBUI_SCRIPT=shot MBUI_SHOT_NAME=loading MBUI_SHOT_DIR=$PWD/out/shot-chat ./_build/native/release/build/sffix/sffix.exe >/dev/null
      cp out/shot-chat/chat-1.png out/shots/mac-chat.png
      cp out/shot-chat/chat-2-up.png out/shots/mac-chat-up.png
      cp out/shot-chat/loading.png out/shots/mac-chat-loading.png
      names="mac-chat mac-chat-up mac-chat-loading" ;;
    web-chat)
      APP=sffix bash scripts/web.sh build >/dev/null
      QUERY=MBUI_FIXTURE=chat NODE_PATH=$PWD/out/node/node_modules node scripts/web-shot.mjs out/shots/web-chat.png ;;
    web-home)
      APP=sffix bash scripts/web.sh build >/dev/null
      NODE_PATH=$PWD/out/node/node_modules node scripts/web-shot.mjs out/shots/web-home.png ;;
    web-kit)
      bash scripts/web.sh build >/dev/null
      QUERY=MBUI_SCREEN=kit NODE_PATH=$PWD/out/node/node_modules node scripts/web-shot.mjs out/shots/web-kit.png ;;
    windows)  # on Windows (Git Bash), not part of the default set
      MODE=release bash scripts/win.sh build >/dev/null
      MODE=release bash scripts/win.sh shot >/dev/null
      cp out/shot-win/main.png out/shots/windows.png ;;
    web)
      bash scripts/web.sh build >/dev/null
      NODE_PATH=$PWD/out/node/node_modules node scripts/web-shot.mjs out/shots/web.png ;;
    ios)
      bash scripts/ios.sh build >/dev/null
      rm -rf out/ios/shots
      BENCH=-1 bash scripts/ios.sh run shot >/dev/null
      for i in $(seq 1 30); do [ -f out/ios/shots/main.png ] && break; sleep 1; done
      cp out/ios/shots/main.png out/shots/ios.png ;;
    android)
      bash scripts/android.sh build >/dev/null
      bash scripts/android.sh emu >/dev/null
      A=$HOME/Library/Android/sdk/platform-tools/adb
      $A -s emulator-5580 shell settings put global sysui_demo_allowed 1
      $A -s emulator-5580 shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null
      $A -s emulator-5580 shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 1200 >/dev/null
      $A -s emulator-5580 shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false >/dev/null
      BENCH=-1 bash scripts/android.sh run
      sleep 4
      $A -s emulator-5580 exec-out screencap -p > out/shots/android.png ;;
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
