#!/bin/bash
# How smoothly an app's chats scroll, on studio: on an emulator of this script's own (AVD rn-perf, port 5702, no
# window, drawn by studio's GPU; the emulator's own software renderer makes every app slow), the APK installed,
# pointed at the dev environment up.sh made (PORT; FILLER=60 there gives a list long enough to scroll), signed in as
# alice if it asks; then strokes up and down the list, and what the system counted of its frames (gfxinfo: janky
# frames, the frame times' percentiles, why the slow ones were slow). The Kotlin app to compare with: its release built
# with -PstillfailDevSignIn, ACTIVITY=fail.still.android/fail.still.android.MainActivity.
#
#   APK=<apk> [ACTIVITY=fail.still.rntrial/.MainActivity] [LABEL=x] bash apps/mobile-rn/scripts/devenv/perf.sh
#   bash apps/mobile-rn/scripts/devenv/perf.sh stop          the emulator stopped and its AVD deleted
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
PORT=${PORT:-8950}
EPORT=5702
AVD=rn-perf
export ANDROID_SERIAL=emulator-$EPORT
a() { "$SDK/platform-tools/adb" "$@" < /dev/null; }
avdmanager() { "$(ls "$SDK"/cmdline-tools/*/bin/avdmanager | head -1)" "$@"; }
ours() { [ "$(a emu avd name 2> /dev/null | head -1 | tr -d '\r')" = "$AVD" ]; }
mkdir -p "$HERE/state"

if [ "${1:-}" = stop ]; then
  if ours; then a emu kill || true; sleep 3; fi
  avdmanager delete avd -n "$AVD" > /dev/null 2>&1 || true
  echo "emulator stopped, AVD $AVD deleted"
  exit 0
fi

if ! ours; then
  if a devices | grep -q "^emulator-$EPORT"; then echo "emulator-$EPORT is someone else's" >&2; exit 1; fi
  [ -d ~/.android/avd/$AVD.avd ] || echo no | avdmanager create avd -n "$AVD" -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_7 > /dev/null
  ANDROID_SDK_ROOT=$SDK python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$SDK/emulator/emulator" -avd "$AVD" -no-window -no-audio -no-boot-anim -no-snapshot -gpu "${GPU:-host}" -port $EPORT > "$HERE/state/perf-emulator.log" 2>&1 < /dev/null &
  disown
  a wait-for-device
  for i in $(seq 1 120); do [ "$(a shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = 1 ] && break; sleep 2; done
  a root > /dev/null; sleep 2
  a shell setprop persist.sys.locale zh-CN
  a shell setprop ctl.restart zygote
  sleep 5
  for i in $(seq 1 60); do [ "$(a shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = 1 ] && a shell pm path android > /dev/null 2>&1 && break; sleep 2; done
  sleep 10
fi

ACTIVITY=${ACTIVITY:-fail.still.rntrial/.MainActivity}
PKG=${ACTIVITY%%/*}
LABEL=${LABEL:-$(basename "${APK:?APK=<the app to measure>}" .apk)}
OUT=$HERE/perf
mkdir -p "$OUT"
UI=$OUT/.ui.xml
dump() { a shell uiautomator dump /sdcard/perf-ui.xml > /dev/null 2>&1; a exec-out cat /sdcard/perf-ui.xml > "$UI" 2> /dev/null; }
at() { python3 "$HERE/ui.py" "$UI" "$@"; }
size=$(a shell wm size | awk '/size/ {print $3}' | tail -1)
W=${size%x*}; H=${size#*x}

a install -r -t -d "$APK" > /dev/null
a shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS > /dev/null 2>&1 || true
a reverse tcp:$PORT tcp:$PORT > /dev/null
a reverse tcp:3340 tcp:3340 > /dev/null
a shell am force-stop "$PKG"
a shell am start -W -n "$ACTIVITY" > /dev/null
# Signed in, its rows there (the list's own rows, not the waiting ones): the newest seeded chat's title.
ROW=${ROW:-首页列表滚动卡顿排查}
for i in $(seq 1 60); do
  dump
  at "$ROW" > /dev/null && break
  if xy=$(at "~用开发账号登录（alice" "~Dev sign-in (alice"); then a shell input tap $xy; sleep 8; fi
  sleep 2
done
at "$ROW" > /dev/null || { echo "$LABEL: no chats after 2 min" >&2; exit 1; }
sleep 5
# CHAT=1: the strokes in that chat (its long answer, a table and code), not in the list.
if [ "${CHAT:-}" = 1 ]; then a shell input tap $(at "$ROW"); sleep 6; fi
# A stroke each way first: what the first scroll lays out once is not what scrolling costs.
stroke() { a shell input swipe $((W / 2)) $1 $((W / 2)) $2 ${3:-250}; }
stroke $((H * 3 / 4)) $((H / 4)); sleep 1; stroke $((H / 4)) $((H * 3 / 4)); sleep 1.5
P=$(a shell pidof "$PKG" | tr -d '\r')
# The CPU each of its threads takes over the strokes alone (main, the JS thread, the render thread, the core's).
a shell "cat /proc/$P/task/*/stat" > "$OUT/.before"
# PROFILE=1: where the time goes meanwhile (simpleperf, by thread and function: Hermes's own frames are not named, and
# React Native's release Hermes has no sampling profiler of its own).
[ "${PROFILE:-}" = 1 ] && { a shell "simpleperf record -p $P -e cpu-clock -f 2000 -g --duration 12 -o /data/local/tmp/perf.data" > /dev/null 2>&1 & }
a shell dumpsys gfxinfo "$PKG" reset > /dev/null
# IDLE=1: no strokes, as long: what it costs doing nothing.
if [ "${IDLE:-}" = 1 ]; then sleep 13; else
  for i in 1 2 3 4 5 6; do stroke $((H * 3 / 4)) $((H / 4)); sleep 0.7; done
  for i in 1 2 3 4 5 6; do stroke $((H / 4)) $((H * 3 / 4)); sleep 0.7; done
fi
a shell dumpsys gfxinfo "$PKG" > "$OUT/$LABEL.txt"
a shell "cat /proc/$P/task/*/stat" > "$OUT/.after"
python3 - "$OUT/.before" "$OUT/.after" > "$OUT/$LABEL.threads" <<'PY'
import re, sys
def read(p):
    d = {}
    for line in open(p, errors="replace"):
        m = re.match(r'(\d+) \((.*)\) \S+ ' + r'(\S+ )' * 10 + r'(\d+) (\d+)', line)
        if m: d[m.group(1)] = (m.group(2), int(m.group(13)) + int(m.group(14)))
    return d
a, b = read(sys.argv[1]), read(sys.argv[2])
rows = sorted(((t - a.get(k, (n, 0))[1], n) for k, (n, t) in b.items()), reverse=True)[:6]
for t, n in rows: print(f"{t / 100:6.2f} s  {n}")
PY
if [ "${PROFILE:-}" = 1 ]; then
  wait
  a shell "simpleperf report -i /data/local/tmp/perf.data --sort comm,dso,symbol --percent-limit 0.7 -n" 2> /dev/null | sed -n '1,90p' > "$OUT/$LABEL.profile"
  a shell "simpleperf report -i /data/local/tmp/perf.data --sort comm --percent-limit 0.5" 2> /dev/null | tail -15 >> "$OUT/$LABEL.profile"
fi
echo "== $LABEL"
grep -a -E "Total frames|Janky frames:|50th percentile|90th percentile|99th percentile|Slow UI|Slow bitmap|Slow issue|Frame deadline missed:" "$OUT/$LABEL.txt" | sed 's/^/  /'
sed 's/^/  thread /' "$OUT/$LABEL.threads"
rm -f "$UI" "$OUT/.before" "$OUT/.after"
