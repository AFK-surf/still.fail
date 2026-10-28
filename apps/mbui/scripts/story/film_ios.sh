#!/bin/bash
# Film 1 on the iPhone Duo simulator (Xcode 27.1, iOS 27.1: Mini1): sffix with the story (MBUI_STORY_B64), driven by
# scripts/motion/<drive>.drive, folded at the start and unfolded by SpringBoard's own display tool (scripts/story/fold.m)
# when the drive says UNFOLD; with REC=1 both screens recorded (out/film/ios-outer.mp4, ios-inner.mp4), with stills
# the screen in use taken where the drive says SHOT (out/film/ios-<name>.png). `film_ios.sh <drive> [build]`.
D="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$D"
drive=${1:?drive}
export MBUI_IOS_DEVICE=sf-film-duo APP=sffix
ID=$(xcrun simctl list devices -j | python3 -c "import json,sys;print([x['udid'] for ds in json.load(sys.stdin)['devices'].values() for x in ds if x['name']=='sf-film-duo'][0])")
# the screens by their size (their ids are made again as the simulator starts): the outer 1398 x 2034, the inner 2007 x 2853
screens() {
  OUTER=$(xcrun simctl io $ID enumerate 2>/dev/null | awk '/UUID:/{u=$2} /Default width: 1398/{print u; exit}')
  INNER=$(xcrun simctl io $ID enumerate 2>/dev/null | awk '/UUID:/{u=$2} /Default width: (2007|2853)/{print u; exit}')
  echo "film_ios: outer $OUTER, inner $INNER"
}
screens
# the simulator's language (its keyboard with it) as the film's: FILM_LANG=en English, Chinese else; set anew, the
# simulator started over for it to take
want_lang=$([ "${FILM_LANG:-zh}" = en ] && echo en-US || echo zh-Hans-CN)
want_locale=$([ "${FILM_LANG:-zh}" = en ] && echo en_US || echo zh_CN)
if ! xcrun simctl spawn $ID defaults read -g AppleLanguages 2>/dev/null | grep -q "\"$want_lang\""; then
  echo "film_ios: the simulator in $want_lang"
  xcrun simctl spawn $ID defaults write -g AppleLanguages -array "$want_lang"
  xcrun simctl spawn $ID defaults write -g AppleLocale "$want_locale"
  xcrun simctl shutdown $ID; xcrun simctl boot $ID; xcrun simctl bootstatus $ID > /dev/null 2>&1; sleep 8; screens
fi
mkdir -p out/story out/film
# the display tool's client: its entitlement in __TEXT,__entitlements, as the simulator reads an app's
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=17.0 -isysroot "$SDK" -fobjc-arc -framework Foundation \
  scripts/story/fold.m -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker scripts/story/fold.ent -o out/story/fold || exit 1
codesign -s - -f out/story/fold 2>/dev/null
fold() { xcrun simctl spawn $ID "$D/out/story/fold" swap 0.64 2>&1 | grep -v "implemented in both"; }
# folded to start, the outer screen lit: the inner screen's picture all black (a few KB as PNG) when it is folded
opened() { rm -f /tmp/sf-film-inner-$$.png; xcrun simctl io $ID screenshot --display=$INNER /tmp/sf-film-inner-$$.png >/dev/null 2>&1; [ "$(stat -f %z /tmp/sf-film-inner-$$.png 2>/dev/null || echo 0)" -gt 300000 ]; }
# (each swap goes to the other screen; one SpringBoard will not take, a transition of its left hanging, is cleared by
# starting the simulator over)
if opened; then
  echo "film_ios: open: folding"; fold; sleep 8
  if opened; then
    echo "film_ios: still open: the simulator started over"
    xcrun simctl shutdown $ID; xcrun simctl boot $ID; xcrun simctl bootstatus $ID > /dev/null 2>&1; sleep 8; screens
    opened && { fold; sleep 3; }
    opened && { echo "film_ios: still open"; exit 1; }
  fi
fi
rm -f /tmp/sf-film-inner-$$.png
[ "${2:-}" = build ] && { bash scripts/ios.sh build > out/story/ios-build.log 2>&1 || { tail -30 out/story/ios-build.log; exit 1; }; tail -1 out/story/ios-build.log; }
# the story: FILM_STORY (iduo by default; iduo-en English), its pictures in it (made by make.py, kept built beside it)
story=${FILM_STORY:-iduo}
[ -f out/story/$story.json ] || cp scripts/story/$story.built.json out/story/$story.json 2>/dev/null || python3 scripts/story/make.py $story.json "$D/out/story/$story.json" || exit 1
export SIMCTL_CHILD_MBUI_STORY_B64=$(base64 -i out/story/$story.json | tr -d '\n')
export SIMCTL_CHILD_MBUI_DRIVE_B64=$(base64 -i scripts/motion/$drive.drive | tr -d '\n')
export SIMCTL_CHILD_MBUI_FIXTURE=chat-story
# (the app's words in the film's language: its device's locale, as the host would say it)
export SIMCTL_CHILD_MBUI_LOCALE=$([ "${FILM_LANG:-zh}" = en ] && echo en-US || echo zh-CN)
xcrun simctl status_bar $ID override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 >/dev/null 2>&1
LOG=$D/out/ios/app.log
# (the simulator records one screen at a time: the outer one till the unfold, the inner one from just before it; when
# each began and when each of the drive's marks was seen, on this Mac's clock, in out/film/ios-times.txt, for the
# compositing to put them on one time line)
now() { python3 -c 'import time;print("%.3f" % time.time())'; }
TIMES=out/film/ios-times.txt
: > $TIMES
# (HEVC: the inner screen, 2007 x 2853, is past what H.264's encoder in hardware takes, 4096 x 2304; encoded so in
# software it lost frames where much of the screen changed at once, the app's own frames all on time)
rec() { # rec NAME DISPLAY
  xcrun simctl io $ID recordVideo --display=$2 --codec=hevc --force out/film/ios-$1.mp4 > out/story/rec-$1.log 2>&1 &
  echo $! > out/story/rec-$1.pid
  # (its first frame once it says it started)
  for i in $(seq 1 100); do grep -q "Recording started" out/story/rec-$1.log && break; sleep 0.05; done
  echo "rec $1 $(now)" >> $TIMES
}
unrec() { [ -f out/story/rec-$1.pid ] || return; kill -INT $(cat out/story/rec-$1.pid) 2>/dev/null; while kill -0 $(cat out/story/rec-$1.pid) 2>/dev/null; do sleep 0.1; done; rm -f out/story/rec-$1.pid; }
rm -f out/film/ios-outer.mp4 out/film/ios-inner.mp4 out/story/rec-*.pid
[ "${REC:-0}" = 1 ] && rec outer $OUTER
T0=$(now)
bash scripts/ios.sh run || exit 1
# the drive's log: UNFOLD swaps the screens; SHOT takes the lit one; PASS or FAIL ends it
lit=$OUTER n=0
tail -n +1 -F "$LOG" 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    "DRIVE AT "*) echo "at $(now) ${line#DRIVE AT }" >> $TIMES ;;
  esac
  case "$line" in
    *"DRIVE LOG UNFOLD"*)
      echo "film_ios: unfold at $(python3 -c "import time;print(round(time.time()-$T0,2))")"
      if [ "${REC:-0}" = 1 ]; then unrec outer; rec inner $INNER; fi
      fold; echo "fold $(now)" >> $TIMES; lit=$INNER ;;
    *"DRIVE LOG SHOT "*) s=${line##*DRIVE LOG SHOT }; echo "film_ios: shot $s: $(xcrun simctl io $ID screenshot --display=$lit "out/film/ios-$s.png" 2>&1 | tail -1)" ;;
    *"DRIVE PASS"*|*"DRIVE FAIL"*) echo "film_ios: $line"; pkill -P $$ tail 2>/dev/null; break ;;
  esac
done
if [ "${REC:-0}" = 1 ]; then unrec outer; unrec inner; ls -la out/film/ios-*.mp4; cat $TIMES; fi
grep -E "^DRIVE (AT|FAIL|PASS)|ios: hinge" "$LOG" | tail -40
