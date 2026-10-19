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
# its end), mac-chat-up (scrolled up: the way to the newest over it) and mac-chat-loading (being read). `composer`
# and `web-composer` are its composer's states (MBUI_FIXTURE=chat-compose|attach|quote|sending|failed):
# mac-composer-<state>, web-composer-<state>. `drive` and `web-drive` are the drive's pages over a made-up drive
# (MBUI_FIXTURE=files|drive|…|reader|…, src/sfapp/drive_fixture.mbt): mac-<mode>, web-<mode>.
# `decide` and `web-decide` are slice 8's (src/sfapp/decide_fixture.mbt's
# modes): the 奏 page (an options card, a text card, none left), an execution history (its steps, its details), the
# chat's sheets (its own, an agent's card, its jobs, a job) and Home with the jobs left up: mac-decide-<mode>,
# web-decide-<mode>.
# `glass` and `web-glass` are the demo's glass screen (MBUI_SCREEN=glass:
# frosted and liquid glass over bands of colour), light and dark (mac-glass, mac-glass-dark); `home` and `chat` also
# give their dark looks (mac-home-dark, mac-chat-dark), `chat` a picture under the bar's glass (mac-chat-glass) and
# its glass drawn solid (mac-chat-solid, as where the system asks for less transparency).
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
mkdir -p out/shots goldens
PLATFORMS=${*:-mac kit home chat composer drive decide glass web web-kit web-home web-chat web-composer web-drive web-decide web-glass ios android}
DRIVE_MODES="files drive drive-sub drive-chosen drive-entry drive-upload drive-empty reader reader-bars reader-contents reader-layout reader-md chat-station-files chat-station-ref"
DECIDE="decisions decisions-text decisions-idle history history-details chat-info chat-agent chat-jobs chat-job home-jobs"
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
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_DARK=1 MBUI_SCRIPT=shot MBUI_SHOT_NAME=home-dark MBUI_SHOT_DIR=$PWD/out/shot-home ./_build/native/release/build/sffix/sffix.exe >/dev/null
      cp out/shot-home/home-dark.png out/shots/mac-home-dark.png
      names="mac-home mac-home-sheet mac-home-swipe mac-home-dark" ;;
    chat)
      APP=sffix MODE=release bash scripts/mac.sh build >/dev/null
      rm -rf out/shot-chat; mkdir -p out/shot-chat
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat MBUI_SCRIPT=chat MBUI_SHOT_DIR=$PWD/out/shot-chat ./_build/native/release/build/sffix/sffix.exe >/dev/null
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat-loading MBUI_SCRIPT=shot MBUI_SHOT_NAME=loading MBUI_SHOT_DIR=$PWD/out/shot-chat ./_build/native/release/build/sffix/sffix.exe >/dev/null
      cp out/shot-chat/chat-1.png out/shots/mac-chat.png
      cp out/shot-chat/chat-2-up.png out/shots/mac-chat-up.png
      cp out/shot-chat/loading.png out/shots/mac-chat-loading.png
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat MBUI_DARK=1 MBUI_SCRIPT=shot MBUI_SHOT_NAME=dark MBUI_SHOT_DIR=$PWD/out/shot-chat ./_build/native/release/build/sffix/sffix.exe >/dev/null
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat MBUI_GLASS=solid MBUI_SCRIPT=shot MBUI_SHOT_NAME=solid MBUI_SHOT_DIR=$PWD/out/shot-chat ./_build/native/release/build/sffix/sffix.exe >/dev/null
      # scrolled so a picture is under the bar's glass and messages under the composer's
      rm -rf out/shot-chat-glass; mkdir -p out/shot-chat-glass
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat MBUI_CHAT_UP=1000 MBUI_SCRIPT=chat MBUI_SHOT_DIR=$PWD/out/shot-chat-glass ./_build/native/release/build/sffix/sffix.exe >/dev/null
      cp out/shot-chat-glass/chat-2-up.png out/shots/mac-chat-glass.png
      cp out/shot-chat/dark.png out/shots/mac-chat-dark.png
      cp out/shot-chat/solid.png out/shots/mac-chat-solid.png
      names="mac-chat mac-chat-up mac-chat-loading mac-chat-glass mac-chat-dark mac-chat-solid" ;;
    glass)
      MODE=release bash scripts/mac.sh build >/dev/null
      rm -rf out/shot-glass; mkdir -p out/shot-glass
      MBUI_BENCH=-1 MBUI_SCREEN=glass MBUI_WIN=390x844 MBUI_SCRIPT=shot MBUI_SHOT_NAME=glass MBUI_SHOT_DIR=$PWD/out/shot-glass ./_build/native/release/build/demo/demo.exe >/dev/null
      MBUI_BENCH=-1 MBUI_SCREEN=glass MBUI_DARK=1 MBUI_WIN=390x844 MBUI_SCRIPT=shot MBUI_SHOT_NAME=glass-dark MBUI_SHOT_DIR=$PWD/out/shot-glass ./_build/native/release/build/demo/demo.exe >/dev/null
      cp out/shot-glass/glass.png out/shots/mac-glass.png
      cp out/shot-glass/glass-dark.png out/shots/mac-glass-dark.png
      names="mac-glass mac-glass-dark" ;;
    web-glass)
      bash scripts/web.sh build >/dev/null
      QUERY=MBUI_SCREEN=glass NODE_PATH=$PWD/out/node/node_modules node scripts/web-shot.mjs out/shots/web-glass.png ;;
    composer)
      # the composer's states over the made-up chat (src/sfapp/chat_fixture.mbt's modes): words of several lines, a
      # picture and a file with them, a quote, a message sending, one failed
      APP=sffix MODE=release bash scripts/mac.sh build >/dev/null
      rm -rf out/shot-composer; mkdir -p out/shot-composer
      names=
      for m in compose attach quote sending failed; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat-$m MBUI_SCRIPT=shot MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-composer ./_build/native/release/build/sffix/sffix.exe >/dev/null
        cp out/shot-composer/$m.png out/shots/mac-composer-$m.png
        names="$names mac-composer-$m"
      done ;;
    drive)
      # the drive's pages over the fixture's made-up drive (src/sfapp/drive_fixture.mbt's modes): 文件, a folder, a folder
      # in it, two rows chosen, a file's sheet, files going up, an empty folder; a text read, with its bars, its
      # contents, its layout; a Markdown file read
      APP=sffix MODE=release bash scripts/mac.sh build >/dev/null
      rm -rf out/shot-drive; mkdir -p out/shot-drive
      names=
      for m in $DRIVE_MODES; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=$m MBUI_SCRIPT=shot MBUI_SHOT_AT=60 MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-drive ./_build/native/release/build/sffix/sffix.exe >/dev/null
        cp out/shot-drive/$m.png out/shots/mac-$m.png
        names="$names mac-$m"
      done ;;
    web-drive)
      APP=sffix bash scripts/web.sh build >/dev/null
      names=
      for m in $DRIVE_MODES; do
        QUERY=MBUI_FIXTURE=$m NODE_PATH=$PWD/out/node/node_modules node scripts/web-shot.mjs out/shots/web-$m.png
        names="$names web-$m"
      done ;;
    decide)
      APP=sffix MODE=release bash scripts/mac.sh build >/dev/null
      rm -rf out/shot-decide; mkdir -p out/shot-decide
      names=
      for m in $DECIDE; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=$m MBUI_SCRIPT=shot MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-decide ./_build/native/release/build/sffix/sffix.exe >/dev/null
        cp out/shot-decide/$m.png out/shots/mac-decide-$m.png
        names="$names mac-decide-$m"
      done ;;
    web-decide)
      APP=sffix bash scripts/web.sh build >/dev/null
      names=
      for m in $DECIDE; do
        QUERY=MBUI_FIXTURE=$m NODE_PATH=$PWD/out/node/node_modules node scripts/web-shot.mjs out/shots/web-decide-$m.png
        names="$names web-decide-$m"
      done ;;
    web-composer)
      APP=sffix bash scripts/web.sh build >/dev/null
      names=
      for m in compose attach quote sending failed; do
        QUERY=MBUI_FIXTURE=chat-$m NODE_PATH=$PWD/out/node/node_modules node scripts/web-shot.mjs out/shots/web-composer-$m.png
        names="$names web-composer-$m"
      done ;;
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
