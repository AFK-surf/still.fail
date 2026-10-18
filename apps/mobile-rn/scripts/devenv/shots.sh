#!/bin/bash
# The same screens of an installed app, found by what they say (uiautomator dump, ui.py), on the emulator
# $ANDROID_SERIAL, against the dev environment up.sh seeded (the app built for its cloud and signed in, or showing its
# dev sign-in, which this taps):
#
#   ANDROID_SERIAL=emulator-5696 bash apps/mobile-rn/scripts/devenv/shots.sh fail.still.rntrial/.MainActivity [out]
#
# out defaults to shots/<package> here. Each screen is <name>.png with <name>.txt beside it (what the dump said there,
# with bounds); a screen not found is named in missing.txt and the rest go on. Labels are tried in Chinese and in
# English. The screens: home-light, home-dark, home-filter-menu, bar-panel (the bottom bar drawn up: the other bars),
# bar-second (the second bar chosen), chat-markdown (+ chat-markdown-up, scrolled up), chat-decision, chat-image,
# composer (the composer focused, the keyboard closed; "LGTM" typed in where adb text input reaches the field),
# chat-info (the chat's "…" sheet), agent-sheet (an agent's name in the chat tapped), history (its card's history row),
# new-chat (the bar's action), search (the field over the chats, "station" looked for), archive (the filter menu's archived), settings
# (+ workspace, usage, appearance, bar-settings: its rows), stations (+ station: its station's page), profiles, files
# (+ drive-folder: still.fail, file-preview: its README.md).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TARGET=${1:?usage: shots.sh <package>/<activity> [out]}
PKG=${TARGET%%/*}
OUT=${2:-$HERE/shots/$PKG}
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
: "${ANDROID_SERIAL:?ANDROID_SERIAL=emulator-<port>: the emulator to use (one of your own)}"
export ANDROID_SERIAL
mkdir -p "$OUT"
# Nothing of an earlier run left to be taken for this one.
rm -f "$OUT"/*.png "$OUT"/*.txt
a() { "$SDK/platform-tools/adb" "$@" < /dev/null; }
UI=$OUT/.ui.xml
dump() { a shell uiautomator dump /sdcard/devenv-ui.xml > /dev/null 2>&1; a exec-out cat /sdcard/devenv-ui.xml > "$UI" 2> /dev/null; }
at() { python3 "$HERE/ui.py" "$UI" "$@"; }
# Taps the first of the labels found now.
tap() { dump; local xy; xy=$(at "$@") || return 1; a shell input tap $xy; }
# Waits (up to WAIT seconds) for one of the labels.
until_seen() { local i; for i in $(seq 1 "${WAIT:-20}"); do dump; at "$@" > /dev/null && return 0; sleep 1; done; return 1; }
shot() { sleep "${SETTLE:-2}"; a exec-out screencap -p > "$OUT/$1.png"; dump; python3 "$HERE/ui.py" "$UI" --list > "$OUT/$1.txt"; echo "$(date +%T) shot $1"; }
miss() { echo "$1: $2 ($(a get-state 2>&1 | head -1))" | tee -a "$OUT/missing.txt"; }
back() { a shell input keyevent 4; sleep 1; }
# The soft keyboard put away, if it is up (an emulator with a hardware keyboard shows none: back would leave the page).
keyboard_away() { a shell dumpsys input_method | grep -q "mInputShown=true" && back; return 0; }
# The app in front again, if something (a back too many) took it away.
in_front() { a shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp" | grep -q "$PKG" || { a shell am start -n "$TARGET" > /dev/null; sleep 4; }; }
size=$(a shell wm size | awk '/size/ {print $3}' | tail -1)
W=${size%x*}
H=${size#*x}

HOME_TITLE="首页列表滚动卡顿排查"
CHATS=("对话" "Chats")
SECOND=("奏" "Decisions")
# A stroke up from the bar at x y (onto the other bar's row: that bar chosen).
stroke() { a shell input swipe "$1" "$2" "$1" $(($2 - H / 7)) 700; sleep 1.5; }
home() {
  # Back to the chats: the bar's first place (from the second bar, the first bar again), else back until it shows.
  local i xy
  for i in 1 2 3 4; do
    in_front
    dump
    at "$HOME_TITLE" > /dev/null && return 0
    if xy=$(at --below $((H * 3 / 4)) "${CHATS[@]}"); then a shell input tap $xy
    elif xy=$(at --below $((H * 3 / 4)) "${SECOND[@]}"); then stroke $xy
    else back; fi
    sleep 1
  done
  until_seen "$HOME_TITLE"
}
open_chat() { home && tap "$1" && until_seen "${2:-$1}"; }

a shell cmd uimode night no > /dev/null
a shell am force-stop "$PKG"
a shell am start -n "$TARGET" > /dev/null
# Signed out: its dev sign-in for alice.
WAIT=40 until_seen "$HOME_TITLE" "~用开发账号登录" "~Dev sign-in" || miss start "neither the chats nor a dev sign-in in 40 s"
if at "~用开发账号登录" "~Dev sign-in" > /dev/null; then
  tap "~用开发账号登录" "~Dev sign-in"
  WAIT=60 until_seen "$HOME_TITLE" || miss sign-in "no chats 60 s after the dev sign-in"
fi

# ── home, light and dark ──
home && shot home-light
a shell cmd uimode night yes > /dev/null
sleep 2
shot home-dark
a shell cmd uimode night no > /dev/null
sleep 2

# ── the home filter menu ──
if tap "~筛选会话" "~Filter chats" "~筛选" "~Filter"; then
  until_seen "我参与的" "Mine" "~Mine" && shot home-filter-menu || miss home-filter-menu "the menu did not show"
  back
else miss home-filter-menu "no filter button"; fi

# ── the bottom bar's other bars: drawn up from the bar ──
# A finger set on the bar and drawn up opens the panel of the other bars; let go over a row there, that bar is chosen.
# bar-panel is taken with the finger still down (then drawn back to the bar and lifted: nothing chosen); bar-second
# after a whole stroke up onto the second bar's row; a stroke from there chooses the first bar again.
home
dump
if xy=$(at --below $((H * 3 / 4)) "${CHATS[@]}"); then
  read -r bx by <<< "$xy"
  a shell input motionevent DOWN "$bx" "$by"
  for d in 20 60 120 200 280 340; do a shell input motionevent MOVE "$bx" $((by - d)); done
  sleep 1
  a exec-out screencap -p > "$OUT/bar-panel.png"
  dump; python3 "$HERE/ui.py" "$UI" --list > "$OUT/bar-panel.txt"; echo "shot bar-panel"
  for d in 200 60 0; do a shell input motionevent MOVE "$bx" $((by - d)); done
  a shell input motionevent UP "$bx" "$by"
  sleep 1.5
  stroke "$bx" "$by"
  dump
  if xy=$(at --below $((H * 3 / 4)) "${SECOND[@]}"); then
    shot bar-second
    read -r bx by <<< "$xy"
    stroke "$bx" "$by"
    dump
    at --below $((H * 3 / 4)) "${CHATS[@]}" > /dev/null || miss bar-back "the first bar was not chosen again"
  else miss bar-second "a stroke up from the bar did not choose the second bar"; fi
else miss bar-panel "no bottom bar"; fi

# ── chats ──
if open_chat "$HOME_TITLE" "~旧 station 不带 rev"; then
  shot chat-markdown
  a shell input swipe $((W / 2)) $((H * 3 / 10)) $((W / 2)) $((H * 8 / 10)) 400
  shot chat-markdown-up
  back
else miss chat-markdown "could not open “$HOME_TITLE”"; fi
if open_chat "发布 0.1.2450 测试版" "现在发布"; then shot chat-decision; back; else miss chat-decision "no card in “发布 0.1.2450 测试版”"; fi
if open_chat "Profile 页的头像裁剪" "~裁剪框从 64 dp"; then
  shot chat-image
  # The composer: tapped, a draft typed, the keyboard put away.
  dump
  if xy=$(at --below $((H * 2 / 3)) "发消息" "~Message" "~回复" "~Reply" "@EditText"); then
    a shell input tap $xy
    sleep 2
    # Typed into the IME (a pinyin keyboard composes Latin letters): enter commits them as they are.
    a shell input text "LGTM"
    a shell input keyevent KEYCODE_ENTER
    sleep 2
    keyboard_away
    shot composer
    # The draft taken out again (so the next run starts the same).
    a shell input keyevent KEYCODE_MOVE_END
    for i in 1 2 3 4 5 6; do a shell input keyevent KEYCODE_DEL; done
    keyboard_away
  else miss composer "no composer field"; fi
  # The chat's sheet ("…"), then an agent's card (its name over its message) and the history its card leads to.
  if tap "~对话信息" "~Chat info"; then
    until_seen "~发起" "~started it" "~最新" "~latest" && shot chat-info || miss chat-info "the sheet did not show"
    back
  else miss chat-info "no “对话信息” in the chat's bar"; fi
  if tap --below $((H / 6)) "Opus 4.7"; then
    until_seen "历史" "History" && shot agent-sheet || miss agent-sheet "the card did not show"
    if tap "历史" "History"; then sleep 2; shot history; back; else miss history "no history row in the card"; fi
    in_front
  else miss agent-sheet "no agent's name in the chat"; fi
  back
else miss chat-image "could not open “Profile 页的头像裁剪”"; fi

# ── a new chat (the bar's action), the search over the chats, the archive (from the filter menu) ──
home
if tap --below $((H * 3 / 4)) "新建对话" "New chat"; then sleep 2; keyboard_away; shot new-chat; back; else miss new-chat "no “新建对话” in the bar"; fi
home
# The search is at the list's top, there once the list is scrolled to it.
a shell input swipe $((W / 2)) $((H * 3 / 10)) $((W / 2)) $((H * 7 / 10)) 300
sleep 1
# "station" typed in (what adb text input reaches): chats and messages found.
# (Shot with the keyboard as it is: put away, back would close the search in one app and not the other.)
if tap "~搜索对话和消息" "~Search chats"; then
  sleep 2; tap "@EditText"; sleep 1; a shell input text station; a shell input keyevent KEYCODE_ENTER; sleep 3; shot search; back; back
else miss search "no search field over the chats"; fi
home
if tap "~筛选会话" "~Filter chats" "~筛选" "~Filter"; then
  if tap "已归档" "Archived"; then sleep 2; shot archive; back; else miss archive "no “已归档” in the filter menu"; back; fi
else miss archive "no filter button"; fi

# ── settings, the places ──
home
if tap "设置" "Settings"; then
  sleep 1; shot settings
  for row in "workspace:Workspace:Workspace" "usage:用量:Usage" "appearance:外观:Appearance" "bar-settings:下方栏:Bottom bar"; do
    IFS=: read -r name zh en <<< "$row"
    if tap --below $((H / 6)) "$zh" "$en"; then sleep 2; shot "$name"; back; else miss "$name" "no “$zh” row in settings"; fi
  done
  back
else miss settings "no settings button"; fi
for place in "stations:~Station:~Stations" "profiles:Profile:Profiles" "files:文件:Files"; do
  IFS=: read -r name zh en <<< "$place"
  home
  if tap --below $((H * 3 / 4)) "$zh" "$en"; then
    shot "$name"
    case $name in
      stations) if tap --above $((H * 3 / 4)) "studio"; then sleep 2; shot station; back; else miss station "no “studio” in the stations"; fi ;;
      files)
        if tap --above $((H * 3 / 4)) "still.fail"; then
          until_seen "README.md" && shot drive-folder || miss drive-folder "no README.md in still.fail"
          if tap "README.md"; then sleep 3; shot file-preview; back; else miss file-preview "no README.md to open"; fi
          back
        else miss drive-folder "no “still.fail” in the files"; fi ;;
    esac
  else miss "$name" "no “${zh#\~}” in the bottom bar"; fi
done
home
rm -f "$UI"
echo "screens in $OUT"
[ -f "$OUT/missing.txt" ] && { echo "missing:"; cat "$OUT/missing.txt"; }
exit 0
