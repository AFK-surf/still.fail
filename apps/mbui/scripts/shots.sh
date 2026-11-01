#!/bin/bash
# Screenshots of still.fail's screens in mbui on macOS (the Mac's host: a window each) and in a browser, to look at:
# out/shots/<name>.png. Not a check, and no references kept for them: what still.fail's screens are held to is
# Android's app, the original.
#   apps/mbui/scripts/shots.sh [kit home chat composer drive decide glass newchat preview settings web-kit web-home …]
# Each one-picture shot is of the frame at a declared moment of the app's own clock, SHOT_MS (1000 ms: mbui's
# MBUI_SHOT_MS, the web's shot_at; the frames 1/60 s apart from 0, the clock still while the app awaits its host), the
# same picture each run whatever the machine.
# `kit` (macOS) and `web-kit` are the kit (APP=sfkit, a phone's window: rich text, Markdown, pages): kit gives mac-kit
# (its first page) and mac-kit-swipe (the next page pushed, then swiped halfway back from the left edge). `home` (macOS)
# and `web-home` are still.fail's Home over made-up chats (APP=sffix, src/sfapp/fixture.mbt) in a phone's window: home
# gives mac-home (the list), mac-home-sheet (the workspaces' sheet) and mac-home-swipe (a chat pushed, swiped halfway
# back). `chat` and `web-chat` are a made-up chat open over it (MBUI_FIXTURE=chat, src/sfapp/chat_fixture.mbt): chat
# gives mac-chat (at its end), mac-chat-up (scrolled up: the way to the newest over it) and mac-chat-loading (being
# read), its dark look (mac-chat-dark), a picture under the bar's glass (mac-chat-glass) and its glass drawn solid
# (mac-chat-solid). `composer` and `web-composer` are its composer's states (MBUI_FIXTURE=chat-compose|attach|quote|
# sending|failed); `cards` and `web-cards` its cards answered from it, Markdown's tables and code, picking words, a link's menu
# (MBUI_FIXTURE=chat-cards|answering|md|pick|link-menu). `drive` and `web-drive` the drive's pages over a made-up drive (src/sfapp/drive_fixture.mbt);
# `decide` and `web-decide` src/sfapp/decide_fixture.mbt's modes; `settings` and `web-settings` the settings' pages
# (src/sfapp/settings/fixture.mbt); `glass` and `web-glass` frosted and liquid glass over bands of colour (APP=sfkit
# MBUI_SCREEN=glass), light and dark; `newchat` and `web-newchat` a new chat, its sheets, the bottom bar's panel and a
# place (src/sfapp/newchat_fixture.mbt); `preview` and `web-preview` a file of a chat open in the preview; `wide` the
# wide frame of a desktop's window (WIDE_WIN, 1280x800) over sffix's modes (WIDE_MODES), light and dark.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
mkdir -p out/shots
# (the moment each picture is of, on the app's clock)
SHOT_MS=1000
export SHOT_MS
PLATFORMS=${*:-kit home chat cards composer drive decide glass newchat preview settings wide web-kit web-home web-chat web-cards web-composer web-drive web-decide web-glass web-newchat web-preview web-settings}
DRIVE_MODES="files drive drive-sub drive-upload drive-download drive-empty reader reader-bars reader-contents reader-layout reader-md chat-station-files chat-station-ref chat-station-file chat-station-sheet"
DECIDE="history history-details chat-info chat-agent chat-jobs chat-job home-jobs chat-letters-info chat-letters chat-letters-open"
PLAYER_MODES="video audio ended opening"
SERVICE_MODES="service service-sized service-restart service-stopped"
SHARE_MODES="share-in share-in-stations share-in-files"
WIDE_MODES=${WIDE_MODES:-home chat settings-appearance files}
SETTINGS_PAGES=${SETTINGS_PAGES:-home home-dark appearance me workspace security vault stations station profiles profile connects memory memory-doc usage archive station-mark station-env station-lower station-versions stations-add stations-existing stations-command first-station adb profile-menu profile-lower profile-login new-profile connect-menu connect-mode connect-run new-connect slack-app vault-off vault-words vault-add vault-editor vault-recover vault-item decisions completion policy bars kept changelog prices run add-people workspace-mark}
if [ ! -d out/node/node_modules/playwright ]; then
  (cd out/node 2>/dev/null || { mkdir -p out/node && cd out/node && npm init -y >/dev/null; }; npm i pngjs playwright >/dev/null 2>&1)
fi
# Built once a run: an app's macOS build (each where its own goes). The browser's shots are taken after the loop, an
# app's together (out/web is one app's build at a time): web_shot queues one of $WAPP's, its query and where it goes,
# for scripts/web-shots.mjs (one browser for all of them).
built=
build_mac() {
  case " $built " in *" $1 "*) return ;; esac
  APP=$1 MODE=release bash scripts/mac.sh build >/dev/null
  built="$built $1"
}
: > out/web-shots.txt
web_shot() { printf '%s\t%s\t%s\n' "$WAPP" "$1" "$2" >> out/web-shots.txt; }
# Now and then node sits there at no CPU, never ending (half an hour seen): what it runs given LIMIT s (perl's alarm,
# which outlives its exec), then once more, then a failure said as such.
limited() {
  local k r
  for k in 1 2; do
    perl -e 'alarm shift; exec @ARGV' ${LIMIT:-600} "$@"
    r=$?
    [ $r = 142 ] || return $r
    echo "$*: stuck ${LIMIT:-600} s (try $k)" >&2
  done
  echo "$*: stuck twice"
  return 1
}
since() { echo "$(( $(date +%s) - $1 )) s"; }
t_all=$(date +%s)
# The macOS platforms MAC_JOBS (3) at a time, each its own app's run and window (the apps built first, once); a
# platform's names said in out/names/<platform>. The browser's only queue theirs here.
case " $PLATFORMS " in *" kit "*|*" glass "*) build_mac sfkit ;; esac
for p in $PLATFORMS; do case $p in web-*|kit|glass) ;; *) build_mac sffix; break ;; esac; done
rm -rf out/names; mkdir -p out/names
# One platform's shots (its names to out/names/<platform>)
shoot() {
  local p=$1 names m d n t_p
  names=$p
  t_p=$(date +%s)
  case $p in
    kit)
      build_mac sfkit
      rm -rf out/shot-kit; mkdir -p out/shot-kit
      MBUI_BENCH=-1 MBUI_SCREEN=kit MBUI_WIN=390x844 MBUI_SCRIPT=kit MBUI_SHOT_DIR=$PWD/out/shot-kit on_screen ./_build/native/release/build/stillfail/sfkit/sfkit.exe >/dev/null
      cp out/shot-kit/kit-1-root.png out/shots/mac-kit.png
      cp out/shot-kit/kit-3-swipe.png out/shots/mac-kit-swipe.png
      names="mac-kit mac-kit-swipe" ;;
    home)
      build_mac sffix
      rm -rf out/shot-home; mkdir -p out/shot-home
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_SCRIPT=home MBUI_SHOT_DIR=$PWD/out/shot-home on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
      cp out/shot-home/home-1.png out/shots/mac-home.png
      cp out/shot-home/home-2-workspaces.png out/shots/mac-home-sheet.png
      cp out/shot-home/home-4-swipe.png out/shots/mac-home-swipe.png
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_DARK=1 MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=home-dark MBUI_SHOT_DIR=$PWD/out/shot-home on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
      cp out/shot-home/home-dark.png out/shots/mac-home-dark.png
      names="mac-home mac-home-sheet mac-home-swipe mac-home-dark" ;;
    chat)
      build_mac sffix
      rm -rf out/shot-chat; mkdir -p out/shot-chat
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat MBUI_SCRIPT=chat MBUI_SHOT_DIR=$PWD/out/shot-chat on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat-loading MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=loading MBUI_SHOT_DIR=$PWD/out/shot-chat on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
      cp out/shot-chat/chat-1.png out/shots/mac-chat.png
      cp out/shot-chat/chat-2-up.png out/shots/mac-chat-up.png
      cp out/shot-chat/loading.png out/shots/mac-chat-loading.png
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat MBUI_DARK=1 MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=dark MBUI_SHOT_DIR=$PWD/out/shot-chat on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat MBUI_GLASS=solid MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=solid MBUI_SHOT_DIR=$PWD/out/shot-chat on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
      # scrolled so a picture is under the bar's glass and messages under the composer's
      rm -rf out/shot-chat-glass; mkdir -p out/shot-chat-glass
      MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat MBUI_CHAT_UP=1000 MBUI_SCRIPT=chat MBUI_SHOT_DIR=$PWD/out/shot-chat-glass on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
      cp out/shot-chat-glass/chat-2-up.png out/shots/mac-chat-glass.png
      cp out/shot-chat/dark.png out/shots/mac-chat-dark.png
      cp out/shot-chat/solid.png out/shots/mac-chat-solid.png
      names="mac-chat mac-chat-up mac-chat-loading mac-chat-glass mac-chat-dark mac-chat-solid" ;;
    glass)
      build_mac sfkit
      rm -rf out/shot-glass; mkdir -p out/shot-glass
      MBUI_BENCH=-1 MBUI_SCREEN=glass MBUI_WIN=390x844 MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=glass MBUI_SHOT_DIR=$PWD/out/shot-glass on_screen ./_build/native/release/build/stillfail/sfkit/sfkit.exe >/dev/null
      MBUI_BENCH=-1 MBUI_SCREEN=glass MBUI_DARK=1 MBUI_WIN=390x844 MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=glass-dark MBUI_SHOT_DIR=$PWD/out/shot-glass on_screen ./_build/native/release/build/stillfail/sfkit/sfkit.exe >/dev/null
      cp out/shot-glass/glass.png out/shots/mac-glass.png
      cp out/shot-glass/glass-dark.png out/shots/mac-glass-dark.png
      names="mac-glass mac-glass-dark" ;;
    web-glass)
      WAPP=sfkit
      web_shot "MBUI_SCREEN=glass" out/shots/web-glass.png ;;
    composer)
      # the composer's states over the made-up chat (src/sfapp/chat_fixture.mbt's modes): words of several lines, a
      # picture and a file with them, a quote, a message sending, one failed
      build_mac sffix
      rm -rf out/shot-composer; mkdir -p out/shot-composer
      names=
      for m in compose attach quote sending failed; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat-$m MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-composer on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
        cp out/shot-composer/$m.png out/shots/mac-composer-$m.png
        names="$names mac-composer-$m"
      done ;;
    cards)
      # the chat's cards as answered from it (src/sfapp/chat_fixture.mbt's modes): the card answered (你 选择了「…」) and
      # 保留 failed a moment ago (its red mark); an option under way (its spinner); an answer with a table and
      # highlighted code (md); a word picked, its handles and bar (pick); a link held, its menu (link-menu)
      build_mac sffix
      rm -rf out/shot-cards; mkdir -p out/shot-cards
      names=
      for m in cards answering md pick link-menu; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat-$m MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-cards on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
        cp out/shot-cards/$m.png out/shots/mac-chat-$m.png
        names="$names mac-chat-$m"
      done ;;
    drive)
      # the drive's pages over the fixture's made-up drive (src/sfapp/drive_fixture.mbt's modes): 文件, a folder, a folder
      # in it, two rows chosen, a file's sheet, files going up, an empty folder; a text read, with its bars, its
      # contents, its layout; a Markdown file read
      build_mac sffix
      rm -rf out/shot-drive; mkdir -p out/shot-drive
      names=
      for m in $DRIVE_MODES; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=$m MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-drive on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
        cp out/shot-drive/$m.png out/shots/mac-$m.png
        names="$names mac-$m"
      done ;;
    web-drive)
      WAPP=sffix
      names=
      for m in $DRIVE_MODES; do
        web_shot "MBUI_FIXTURE=$m" out/shots/web-$m.png
        names="$names web-$m"
      done ;;
    decide)
      build_mac sffix
      rm -rf out/shot-decide; mkdir -p out/shot-decide
      names=
      for m in $DECIDE; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=$m MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-decide on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
        cp out/shot-decide/$m.png out/shots/mac-decide-$m.png
        names="$names mac-decide-$m"
      done ;;
    web-decide)
      WAPP=sffix
      names=
      for m in $DECIDE; do
        web_shot "MBUI_FIXTURE=$m" out/shots/web-decide-$m.png
        names="$names web-decide-$m"
      done ;;
    newchat)
      # a new chat, its station's sheet, its run picker; the bar's panel of the other bar; a place's page
      build_mac sffix
      rm -rf out/shot-newchat; mkdir -p out/shot-newchat
      names=
      for m in newchat newchat-station newchat-model newchat-preset newchat-preset-new newchat-preset-edit newchat-preset-add newchat-preset-new-add newchat-preset-new-browse newchat-preset-picked home-bars place; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=$m MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-newchat on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
        cp out/shot-newchat/$m.png out/shots/mac-newchat-$m.png
        names="$names mac-newchat-$m"
      done ;;
    web-newchat)
      WAPP=sffix
      names=
      for m in newchat newchat-station newchat-model newchat-preset newchat-preset-new newchat-preset-edit newchat-preset-add newchat-preset-new-add newchat-preset-new-browse newchat-preset-picked home-bars place; do
        web_shot "MBUI_FIXTURE=$m" out/shots/web-newchat-$m.png
        names="$names web-newchat-$m"
      done ;;
    preview)
      # the file preview over made-up files (src/sfapp/preview_fixture.mbt): a picture, a PDF (drawn by the system),
      # a video (its player waiting on reads never answered), a page of HTML (a web view, a while to load), code,
      # Markdown, a table, a file that cannot be shown: mac-preview-<what>
      build_mac sffix
      rm -rf out/shot-preview; mkdir -p out/shot-preview
      names=
      for m in image pdf video audio html code md csv none step swipe; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=chat-preview-$m MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-preview on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
        cp out/shot-preview/$m.png out/shots/mac-preview-$m.png
        names="$names mac-preview-$m"
      done ;;
    web-preview)
      WAPP=sffix
      names=
      for m in image pdf video audio html code md csv none step swipe; do
        web_shot "MBUI_FIXTURE=chat-preview-$m" out/shots/web-preview-$m.png
        names="$names web-preview-$m"
      done ;;
    player)
      # the drive's player over made-up films (src/sfapp/play_fixture.mbt): an episode paused with its subtitle, a song,
      # an episode at its end with the next offered, one still opening (its reads never answered)
      build_mac sffix
      rm -rf out/shot-player; mkdir -p out/shot-player
      names=
      for m in $PLAYER_MODES; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=player-$m MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-player on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
        cp out/shot-player/$m.png out/shots/mac-player-$m.png
        names="$names mac-player-$m"
      done ;;
    web-player)
      WAPP=sffix
      names=
      for m in $PLAYER_MODES; do
        web_shot "MBUI_FIXTURE=player-$m" out/shots/web-player-$m.png
        names="$names web-player-$m"
      done ;;
    service)
      # a web service's page over made-up answers of its station (src/sfapp/service_fixture.mbt): fitted, a phone's
      # size on the canvas, being started again, stopped (the page a web view: a while to load)
      build_mac sffix
      rm -rf out/shot-service; mkdir -p out/shot-service
      names=
      for m in $SERVICE_MODES; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=$m MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-service on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
        cp out/shot-service/$m.png out/shots/mac-$m.png
        names="$names mac-$m"
      done ;;
    web-service)
      WAPP=sffix
      names=
      for m in $SERVICE_MODES; do
        web_shot "MBUI_FIXTURE=$m" out/shots/web-$m.png
        names="$names web-$m"
      done ;;
    share)
      # what another app shares in: the sheet of chats over Home, its stations' choice opened
      build_mac sffix
      rm -rf out/shot-share; mkdir -p out/shot-share
      names=
      for m in $SHARE_MODES; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=$m MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-share on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
        cp out/shot-share/$m.png out/shots/mac-$m.png
        names="$names mac-$m"
      done ;;
    web-share)
      WAPP=sffix
      names=
      for m in $SHARE_MODES; do
        web_shot "MBUI_FIXTURE=$m" out/shots/web-$m.png
        names="$names web-$m"
      done ;;
    wide)
      # the wide frame (src/sfapp/wide.mbt) at a desktop's size, light and dark: mac-wide-<mode>[-dark]
      build_mac sffix
      rm -rf out/shot-wide; mkdir -p out/shot-wide
      names=
      for m in $WIDE_MODES; do
        for d in 0 1; do
          n=mac-wide-$m$([ $d = 1 ] && echo -dark)
          MBUI_BENCH=-1 MBUI_WIN=${WIDE_WIN:-1280x800} MBUI_DARK=$d MBUI_FIXTURE=$m MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=$n MBUI_SHOT_DIR=$PWD/out/shot-wide on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
          cp out/shot-wide/$n.png out/shots/$n.png
          names="$names $n"
        done
      done ;;
    settings)
      build_mac sffix
      rm -rf out/shot-settings; mkdir -p out/shot-settings
      names=
      for m in $SETTINGS_PAGES; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=settings-$m MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-settings on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
        cp out/shot-settings/$m.png out/shots/mac-settings-$m.png
        names="$names mac-settings-$m"
      done ;;
    web-settings)
      WAPP=sffix
      names=
      for m in $SETTINGS_PAGES; do
        web_shot "MBUI_FIXTURE=settings-$m" out/shots/web-settings-$m.png
        names="$names web-settings-$m"
      done ;;
    web-composer)
      WAPP=sffix
      names=
      for m in compose attach quote sending failed; do
        web_shot "MBUI_FIXTURE=chat-$m" out/shots/web-composer-$m.png
        names="$names web-composer-$m"
      done ;;
    web-cards)
      WAPP=sffix
      names=
      for m in cards answering md pick link-menu; do
        web_shot "MBUI_FIXTURE=chat-$m" out/shots/web-chat-$m.png
        names="$names web-chat-$m"
      done ;;
    notify)
      build_mac sffix
      rm -rf out/shot-notify; mkdir -p out/shot-notify
      for m in chat-flash chat-flash-mine settings-notify-off; do
        MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=$m MBUI_SCRIPT=shot MBUI_SHOT_MS=$SHOT_MS MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/shot-notify on_screen ./_build/native/release/build/stillfail/sffix/sffix.exe >/dev/null
        cp out/shot-notify/$m.png out/shots/mac-notify-${m#chat-}.png
      done
      names="mac-notify-flash mac-notify-flash-mine mac-notify-settings-notify-off" ;;
    web-notify)
      WAPP=sffix
      names=""
      for m in chat-flash chat-flash-mine settings-notify-off; do
        web_shot "MBUI_FIXTURE=$m" out/shots/web-notify-${m#chat-}.png
        names="$names web-notify-${m#chat-}"
      done ;;
    web-chat)
      WAPP=sffix
      web_shot "MBUI_FIXTURE=chat" out/shots/web-chat.png ;;
    web-home)
      WAPP=sffix
      web_shot "" out/shots/web-home.png ;;
    web-kit)
      WAPP=sfkit
      web_shot "MBUI_SCREEN=kit" out/shots/web-kit.png ;;
  esac
  echo "$names" > out/names/$p
  echo "$p: $(since $t_p)" >&2
}
fail=0
all=
# MAC_JOBS (3) at a time: a token each, read from a FIFO before one starts and written back when it ends (a slot
# waited for as the one before lets it go, no time)
SLOTS=out/shot-slots.fifo
rm -f $SLOTS && mkfifo $SLOTS && exec 4<>$SLOTS && rm -f $SLOTS
for _ in $(seq ${MAC_JOBS:-3}); do echo >&4; done
for p in $PLATFORMS; do
  case $p in
    web-*) shoot $p ;;
    *)
      read -u 4
      { shoot $p; echo >&4; } & ;;
  esac
done
wait
exec 4>&-
for p in $PLATFORMS; do all="$all $(cat out/names/$p)"; done
for a in $(cut -f1 out/web-shots.txt | sort -u); do
  t_p=$(date +%s)
  APP=$a bash scripts/web.sh build >/dev/null
  awk -F'\t' -v a=$a '$1 == a { print $2 "\t" $3 }' out/web-shots.txt > out/web-shots-$a.txt
  NODE_PATH=$PWD/out/node/node_modules limited node scripts/web-shots.mjs out/web-shots-$a.txt || fail=1
  echo "web $a: $(grep -c . out/web-shots-$a.txt) shots in $(since $t_p)" >&2
done
echo "out/shots:$all" >&2
echo "all in $(since $t_all)" >&2
exit $fail
