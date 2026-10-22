#!/bin/bash
# Android's streams (dev.mbui.Streams, android_host.c mb_host_stream_*) through streamdemo's H.264, on the emulator
# scripts/android.sh runs (AVD, EMU_PORT as there; the app built: APP=streamdemo scripts/android.sh build, emu):
#   plain     every frame said shown ("STREAM done")
#   reopen    the stream closed while its decoder holds frames, a new one fed from the start (MBUI_STREAM_REOPEN):
#             the closed one's SurfaceTexture let go only once its decoder has stopped
#   away      the app sent behind and brought back mid-stream (its surface let go and made anew): the frames still
#             said shown
#   thrown    a Java exception out of Streams.show (MBUI_STREAM_THROW_SHOW=5: the 5th throws): the host says it
#             (System.err) and clears it, not left pending for the next JNI call (CheckJNI would end the app): the
#             frames still said shown
#   input-failed / start-failed   a codec call throws synchronously while queuing a frame / starting the reopened
#             decoder: no process crash, every submitted frame acknowledged, and the app told the decoder broke
#   anew      the activity made anew mid-stream: sent behind, the configuration changed meanwhile in a way it does
#             not take itself (the fonts' weight), brought back. Behind, its decoder put a frame on the SurfaceTexture
#             and said it decoded; back, a new GL context, every stream's SurfaceTexture made anew (Streams.lost)
#             before the frame that takes that word: the frame told on the old one let go, not latched from it (a
#             SurfaceTexture abandoned: updateTexImage throws, and CheckJNI ends the app on the exception left
#             pending). The decoder's thread held 1.5 s as the context is lost (MBUI_STREAM_HOLD_DECODER, as on a
#             CPU it does not get), so that frame comes before anything the decoder does. The decoder broken once at
#             least, the frames still said shown
# Each fails on the app's end (a fatal signal, an uncaught exception, CheckJNI) or a Java exception the host caught
# out of Streams (System.err: android_host.c streams_threw) or an updateTexImage that failed; the app's log of each in
# out/android/streams/CASE.log. Exit 0 when every case passed.
set -u
D="$(cd "$(dirname "$0")" && pwd)"
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
ADB=$SDK/platform-tools/adb
SERIAL=emulator-${EMU_PORT:-5580}
APP_ID=${MBUI_APP_ID:-dev.mbui.demo}
O=out/android/streams
rm -rf $O && mkdir -p $O
# the app's end, its own (another app's crash on the emulator is not: the system's own ending under a small memory)
END='Fatal signal .*\(dev\.mbui|Process: dev\.mbui|JNI DETECTED'
BAD="$END|System.err|updateTexImage:|stream [0-9]+: (the H.264 decoder failed|no H.264 decoder)"
failed=0

# the app's log and the activity manager's events from now, into $O/$1.log (logcat's own process: $LC)
log_from_now() {
  $ADB -s $SERIAL logcat -b all -c
  $ADB -s $SERIAL logcat -b main,crash,events -v brief > $O/$1.log 2>&1 &
  LC=$!
}

# until a line matching $2 (or the app's end) is on $1's log, 120 s at most for a run that hangs
wait_line() {
  "$D/chk" logwait --log $O/$1.log --line "$2|$END" --deadline 120 >/dev/null
}

# $1's log: STREAM done, $2 brokens at least, nothing bad; with $3 (a line the case brings about: a Java exception the
# host caught), that line there and System.err not bad
judge() {
  kill $LC 2>/dev/null
  wait $LC 2>/dev/null
  local bad pid want=${2:-0} expect=${3:-} b=$BAD
  [ -n "$expect" ] && b="$END|updateTexImage:"
  # (the app's own lines: its pid, as its log says it)
  pid=$(grep -a 'I/mbui .*activity onCreate' $O/$1.log | head -1 | sed -E 's/.*\( *([0-9]+)\).*/\1/')
  bad=$(grep -aE "$b" $O/$1.log | grep -aE "\( *${pid:-x}\)|$APP_ID" | head -5)
  # A deliberately injected exception is expected; any other decoder error in that run still fails.
  if [ -n "$expect" ]; then
    bad="$bad$(grep -aE 'System.err|stream [0-9]+: (the H.264 decoder failed|no H.264 decoder)' $O/$1.log | grep -aE "\( *${pid:-x}\)|$APP_ID" | grep -avE "$expect|System.err.*at " | head -5)"
    grep -aqE "$expect" $O/$1.log || bad="$bad MISSING: $expect"
  fi
  if [ "$(grep -ac 'STREAM done' $O/$1.log)" -ge 1 ] && [ -z "$bad" ] && [ "$(grep -ac 'STREAM broken' $O/$1.log)" -ge "$want" ]; then
    echo "PASS $1 ($(grep -ac 'STREAM shown' $O/$1.log) shown, $(grep -ac 'STREAM broken' $O/$1.log) broken)"
  else
    echo "FAIL $1"
    [ -n "$bad" ] && echo "$bad"
    grep -a 'I/mbui' $O/$1.log | tail -5
    failed=1
  fi
}

run() {
  ENV="MBUI_STREAM=h264${1:+;$1}" "$D/android.sh" run >/dev/null
}

log_from_now plain
run
wait_line plain 'STREAM done'
judge plain

log_from_now reopen
run "MBUI_STREAM_REOPEN=3"
wait_line reopen 'STREAM done'
judge reopen

log_from_now away
run
wait_line away 'STREAM shown 500'
$ADB -s $SERIAL shell input keyevent KEYCODE_HOME
wait_line away 'wm_on_stop_called.*dev\.mbui\.MainActivity'
$ADB -s $SERIAL shell am start -n $APP_ID/dev.mbui.MainActivity >/dev/null
wait_line away 'STREAM done'
judge away

log_from_now thrown
run "MBUI_STREAM_THROW_SHOW=5"
wait_line thrown 'STREAM done'
judge thrown 0 'System.err.*RuntimeException: MBUI_STREAM_THROW_SHOW: show 5'

log_from_now input-failed
run "MBUI_STREAM_FAIL_INPUT=5"
wait_line input-failed 'STREAM done'
judge input-failed 1 'stream [0-9]+: the H.264 decoder failed: java.lang.IllegalStateException: MBUI_STREAM_FAIL_INPUT: input 5'

log_from_now start-failed
run "MBUI_STREAM_REOPEN=3;MBUI_STREAM_FAIL_START=2"
wait_line start-failed 'STREAM done'
judge start-failed 1 'stream [0-9]+: no H.264 decoder: java.lang.IllegalStateException: MBUI_STREAM_FAIL_START: start 2'

log_from_now anew
$ADB -s $SERIAL shell settings put secure font_weight_adjustment 0
run "MBUI_STREAM_HOLD_DECODER=1500"
wait_line anew 'STREAM shown 300'
$ADB -s $SERIAL shell input keyevent KEYCODE_HOME
wait_line anew 'wm_on_stop_called.*dev\.mbui\.MainActivity'
$ADB -s $SERIAL shell settings put secure font_weight_adjustment 300
$ADB -s $SERIAL shell am start -n $APP_ID/dev.mbui.MainActivity >/dev/null
wait_line anew 'activity onCreate \(restored\)'
wait_line anew 'decoder held 1500 ms'
wait_line anew 'STREAM broken'
wait_line anew 'STREAM done'
$ADB -s $SERIAL shell settings put secure font_weight_adjustment 0
judge anew 1

exit $failed
