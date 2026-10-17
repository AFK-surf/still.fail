#!/bin/bash
# shots.sh's screens on the iOS simulator (studio): the app installed there (scripts/sim.sh, built for the dev cloud
# up.sh seeded), found and tapped through AXe (https://github.com/cameroncooke/AXe: `axe describe-ui` is its
# accessibility tree, ios-ui.py reads it; taps, swipes and typing without the Simulator app's window), signed in as
# alice if it asks. Back is a swipe in from the left edge, as a finger does.
#
#   AXE=<path to axe> SIM=rn-ios-wt bash apps/mobile-rn/scripts/devenv/ios-shots.sh [out]
#
# out defaults to shots/ios here; each screen <name>.png with <name>.txt beside it, a screen not found in missing.txt.
# The screens: home-light, home-dark, home-filter-menu, bar-second, chat-markdown (+ chat-markdown-up), chat-decision,
# chat-image, composer, settings, stations, profiles, files.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
APP=$(cd "$HERE/../.." && pwd)
OUT=${1:-$HERE/shots/ios}
AXE=${AXE:-axe}
APP_ID=fail.still.rntrial
U=$(SIM=${SIM:-rn-trial} bash "$APP/scripts/sim.sh")
mkdir -p "$OUT"
rm -f "$OUT"/*.png "$OUT"/*.txt
UI=$OUT/.ui.json
x() { "$AXE" "$@" --udid "$U" < /dev/null; }
# iOS's own asking whether the app may notify (simctl privacy has no notifications) hides the app from AXe while it is
# up: allowed when seen, as ref.sh grants it on Android.
dump() {
  x describe-ui > "$UI" 2>&1
  local xy
  if xy=$(python3 "$HERE/ios-ui.py" "$UI" "~想给你发送通知" "~Would Like to Send You Notifications" > /dev/null && python3 "$HERE/ios-ui.py" "$UI" "允许" "Allow"); then
    "$AXE" tap -x "${xy% *}" -y "${xy#* }" --udid "$U" > /dev/null < /dev/null; sleep 1; x describe-ui > "$UI" 2>&1
  fi
}
at() { python3 "$HERE/ios-ui.py" "$UI" "$@"; }
tapxy() { x tap -x "$1" -y "$2" > /dev/null; }
tap() { dump; local xy; xy=$(at "$@") || return 1; tapxy $xy; }
until_seen() { local i; for i in $(seq 1 "${WAIT:-20}"); do dump; at "$@" > /dev/null && return 0; sleep 1; done; return 1; }
shot() { sleep "${SETTLE:-2}"; xcrun simctl io "$U" screenshot "$OUT/$1.png" > /dev/null 2>&1; dump; at --list > "$OUT/$1.txt"; echo "$(date +%T) shot $1"; }
# A screen not found: said, and what showed instead kept beside it (miss-<name>.png/.txt).
miss() {
  echo "$1: $2" | tee -a "$OUT/missing.txt"
  xcrun simctl io "$U" screenshot "$OUT/miss-$1.png" > /dev/null 2>&1; dump; at --list > "$OUT/miss-$1.txt"
}
# The size in points (what taps are given in): the app's own element, the whole screen.
dump
read -r W H <<< "$(python3 -c "
import json,sys
t=open('$UI').read(); t=t[min(i for i in (t.find('['), t.find('{')) if i >= 0):]
d=json.JSONDecoder().raw_decode(t)[0]; d=d[0] if isinstance(d,list) else d; f=d['frame']; print(round(f['width']), round(f['height']))" 2>/dev/null || echo "402 874")"
back() { x swipe --start-x 2 --start-y $((H / 2)) --end-x $((W * 3 / 4)) --end-y $((H / 2)) --duration 0.3 > /dev/null; sleep 1; }

HOME_TITLE="首页列表滚动卡顿排查"
CHATS=("对话" "Chats")
SECOND=("奏" "Decisions")
stroke() { x swipe --start-x "$1" --start-y "$2" --end-x "$1" --end-y $(($2 - H / 7)) --duration 0.7 > /dev/null; sleep 1.5; }
home() {
  local i xy
  for i in 1 2 3 4; do
    dump
    at "$HOME_TITLE" > /dev/null && return 0
    if xy=$(at --below $((H * 3 / 4)) "${CHATS[@]}"); then tapxy $xy
    elif xy=$(at --below $((H * 3 / 4)) "${SECOND[@]}"); then stroke $xy
    else back; fi
    sleep 1
  done
  until_seen "$HOME_TITLE"
}
# A row above the bar (one under the bar's action would be the action tapped).
open_chat() { home && tap --above $((H * 3 / 4)) "$1" && until_seen "${2:-$1}"; }

xcrun simctl ui "$U" appearance light
xcrun simctl terminate "$U" $APP_ID 2> /dev/null
xcrun simctl launch "$U" $APP_ID > /dev/null
WAIT=40 until_seen "$HOME_TITLE" "~用开发账号登录" "~Dev sign-in" || miss start "neither the chats nor a dev sign-in in 40 s"
if at "~用开发账号登录" "~Dev sign-in" > /dev/null; then
  tap "~用开发账号登录（alice" "~Dev sign-in (alice"
  WAIT=60 until_seen "$HOME_TITLE" || miss sign-in "no chats 60 s after the dev sign-in"
fi

home && shot home-light
xcrun simctl ui "$U" appearance dark
shot home-dark
xcrun simctl ui "$U" appearance light
sleep 2

if tap "~筛选会话" "~Filter chats" "~筛选" "~Filter"; then
  until_seen "我参与的" "Mine" "~Mine" && shot home-filter-menu || miss home-filter-menu "the menu did not show"
  tap "~筛选会话" "~Filter chats" "~筛选" "~Filter" || back
else miss home-filter-menu "no filter button"; fi

home
dump
if xy=$(at --below $((H * 3 / 4)) "${CHATS[@]}"); then
  stroke $xy
  dump
  if xy=$(at --below $((H * 3 / 4)) "${SECOND[@]}"); then
    shot bar-second
    stroke $xy
    dump
    at --below $((H * 3 / 4)) "${CHATS[@]}" > /dev/null || miss bar-back "the first bar was not chosen again"
  else miss bar-second "a stroke up from the bar did not choose the second bar"; fi
else miss bar-second "no bottom bar"; fi

if open_chat "$HOME_TITLE" "~旧 station 不带 rev"; then
  shot chat-markdown
  x swipe --start-x $((W / 2)) --start-y $((H * 3 / 10)) --end-x $((W / 2)) --end-y $((H * 8 / 10)) --duration 0.4 > /dev/null
  shot chat-markdown-up
  back
else miss chat-markdown "could not open “$HOME_TITLE”"; fi
# iOS reads an option and its note as one ("现在发布, 发到测试频道…").
if open_chat "发布 0.1.2450 测试版" "~现在发布"; then shot chat-decision; back; else miss chat-decision "no card in “发布 0.1.2450 测试版”"; fi
if open_chat "Profile 页的头像裁剪" "~裁剪框从 64 dp"; then
  shot chat-image
  dump
  if xy=$(at --below $((H * 2 / 3)) "发消息" "~Message" "~回复" "~Reply" "@TextField" "@TextArea" "@TextView"); then
    tapxy $xy
    sleep 2
    x type "LGTM" > /dev/null
    sleep 1
    shot composer
    for i in 1 2 3 4; do x key 42 > /dev/null; done
  else miss composer "no composer field"; fi
  back
else miss chat-image "could not open “Profile 页的头像裁剪”"; fi

home
if tap "设置" "Settings"; then sleep 1; shot settings; back; else miss settings "no settings button"; fi
for place in "stations:~Station:~Stations" "profiles:Profile:Profiles" "files:文件:Files"; do
  IFS=: read -r name zh en <<< "$place"
  home
  if tap --below $((H * 3 / 4)) "$zh" "$en"; then shot "$name"; else miss "$name" "no “${zh#\~}” in the bottom bar"; fi
done
home
rm -f "$UI"
echo "screens in $OUT"
[ -f "$OUT/missing.txt" ] && { echo "missing:"; cat "$OUT/missing.txt"; }
exit 0
