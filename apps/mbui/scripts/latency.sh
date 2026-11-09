#!/bin/bash
# How long input takes to show on this Mac's screen: still.fail over its made-up chats (APP=sffix, built for Wasm and
# run by mbui's native shell, scripts/wasm-app.sh; NATIVE=1 the native app, scripts/mac.sh's), each run a process of
# its own whose host measures it (mbui's src/host/mac_latency.h says how and what each part is), driven to its place by
# scripts/latency/<mode>.drive. Each mode RUNS times (6), each run's line and the median of them: the window server
# settles in a state that lasts a run, so what is compared is medians. OTHER=<a program> runs that one too, in turn
# with this one (another checkout's out/wasm-app/sffix, a build before a change), its lines marked B; EXE=<a program>
# runs that one, nothing built (a build copied to a Mac with a screen).
# A display's own times want its screen on and unlocked: locked, it shows none of the app's frames.
# PLATFORM=android: the same on a phone (mbui's Latency.java), sffix's native APK (scripts/android.sh, installed as
# fail.still.android.dev), started with the run's drive (scripts/latency/android/<mode>.drive where there is one) and
# its line read off the log; SERIAL the phone's, ADB_FLAGS what else adb is given (-P PORT), DISPLAY_ID a display of it
# to start on (else its own). A debug build takes an intent's drive only with debug.mbui.hooks 1 (set here).
# For people, never a check: no test or CI step runs it.
#   scripts/latency.sh [MODES]        type scroll drag (by default), anim
#   EVENTS=300 WARMUP=30 (mac_latency.h's MBUI_LATENCY_EVENTS, _WARMUP); WIN=1280x800 (大屏)
set -u
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
modes=${1:-type scroll drag}
if [ "${PLATFORM:-mac}" = android ]; then
  adb_() { adb ${ADB_FLAGS:-} ${SERIAL:+-s $SERIAL} "$@"; }
  if [ "${BUILD:-1}" = 1 ]; then
    APP=sffix bash scripts/android.sh build > out/latency-build.log 2>&1 || { tail -30 out/latency-build.log; exit 1; }
    adb_ install -r android/app/build/outputs/apk/debug/app-debug.apk > /dev/null || exit 1
  fi
  adb_ shell setprop debug.mbui.hooks 1
elif [ -n "${EXE:-}" ]; then
  exe=$EXE
elif [ "${NATIVE:-0}" = 1 ]; then
  APP=sffix MODE=release bash scripts/mac.sh build > out/latency-build.log 2>&1 || { tail -30 out/latency-build.log; exit 1; }
  exe=$A/_build/native/release/build/stillfail/sffix/sffix.exe
else
  APP=sffix bash scripts/wasm-app.sh build > out/latency-build.log 2>&1 || { tail -30 out/latency-build.log; exit 1; }
  exe=$A/out/wasm-app/sffix
fi
fields="mean p50 p90 p99 queue handle tick build upload drawable encode screen wait blocked new notshown events refresh"
# (Android's parts: to the drawing thread and through the app's handling there, the frame, to the compositor's latch)
[ "${PLATFORM:-mac}" = android ] && fields="mean p50 p90 p99 queue handle gl tick build latch screen new notshown events refresh"
# one run of mode $2 on the phone: its LATENCY line
run_android() {
  local f=$D/latency/android/$1.drive
  [ -f "$f" ] || f=$D/latency/$1.drive
  adb_ shell am force-stop fail.still.android.dev
  adb_ logcat -c
  local fixture=chat-long
  [ $1 = anim ] && fixture=chat-answering
  adb_ shell am start ${DISPLAY_ID:+--display $DISPLAY_ID} -n fail.still.android.dev/dev.mbui.MainActivity --es env \
    "'MBUI_FIXTURE=$fixture;MBUI_LATENCY_EVENTS=${EVENTS:-300};MBUI_LATENCY_WARMUP=${WARMUP:-30};MBUI_DRIVE_B64=$(base64 < "$f" | tr -d '\n')'" > /dev/null
  # (the run's line, or its end without one; at most three minutes)
  perl -e 'alarm shift; exec @ARGV' 180 adb ${ADB_FLAGS:-} ${SERIAL:+-s $SERIAL} logcat -v raw -s mbui:I AndroidRuntime:E \
    -e '^LATENCY mode|^DRIVE (FAIL|END)|FATAL EXCEPTION' -m 1
}
# one run of mode $2 by program $1: its LATENCY line
run() {
  if [ "${PLATFORM:-mac}" = android ]; then run_android $2; return; fi
  local fixture=chat-long
  [ $2 = anim ] && fixture=chat-answering
  (
    export MBUI_LATENCY=1 MBUI_LATENCY_EVENTS=${EVENTS:-300} MBUI_LATENCY_WARMUP=${WARMUP:-30} MBUI_FIXTURE=$fixture \
      MBUI_WIN=${WIN:-1280x800} MBUI_DRIVE="$(cat "$D/latency/$2.drive")"
    on_screen "$1" 2>&1 | grep -E '^LATENCY|^DRIVE (FAIL|END)'
  )
}
# the median of field $1 in the lines on stdin
median() {
  tr ' ' '\n' | sed -n "s/^$1=//p" | sort -g | awk '{ v[NR] = $1 } END { if (NR) print (NR % 2 ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2) }'
}
summary() {
  local lines=$1 out="" f
  for f in $fields; do out="$out $f=$(echo "$lines" | median $f)"; done
  echo "$out $(echo "$lines" | grep -o 'clock=[a-z]*' | sort -u | tr '\n' ' ')"
}
# (said, not refused: a Mac with no display, Studio's, gives no presentedTime locked or not, and its runs are timed by
# when the window server says it presented each frame, clock=told: mac_latency.h)
if [ "${PLATFORM:-mac}" = mac ] && ioreg -l -w0 | grep -q '"CGSSessionScreenIsLocked"=Yes'; then
  echo "latency: the screen is locked: a display shows none of the app's frames (clock=told at best)" >&2
fi
# (the display kept awake, as someone at it would: asleep, nothing is shown)
if [ "${PLATFORM:-mac}" = mac ]; then
  caffeinate -u -t 3600 &
  awake=$!
  trap 'kill $awake 2>/dev/null' EXIT
fi
code=0
for mode in $modes; do
  [ -f "$D/latency/$mode.drive" ] || [ -f "$D/latency/android/$mode.drive" ] || { echo "latency: no mode $mode (scripts/latency/*.drive)"; exit 2; }
  a=""
  b=""
  for k in $(seq 1 "${RUNS:-6}"); do
    l=$(run "$exe" $mode)
    echo "$mode A run $k: ${l#LATENCY }"
    case $l in LATENCY*) a="$a$l"$'\n' ;; *) code=1 ;; esac
    if [ -n "${OTHER:-}" ]; then
      l=$(run "$OTHER" $mode)
      echo "$mode B run $k: ${l#LATENCY }"
      case $l in LATENCY*) b="$b$l"$'\n' ;; *) code=1 ;; esac
    fi
  done
  echo "$mode A median:$(summary "$a")"
  [ -n "${OTHER:-}" ] && echo "$mode B median:$(summary "$b")"
done
exit $code
