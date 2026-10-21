#!/bin/bash
# The soft keyboard as Android's host asks for it (Host.java's owed show), through devicedemo's key catcher, focused
# in its first frame, on the emulator scripts/android.sh runs (AVD, EMU_PORT as there; the app built: APP=devicedemo
# scripts/android.sh build, emu). The emulator has a hardware keyboard: show_ime_with_hard_keyboard is set, as the
# soft one would not come up otherwise. On an emulator just booted, the first case is the first launch after a boot
# (the IME's window not made yet as the app starts).
#   up        launched: the keyboard up with nothing typed (devicedemo says its height, "IME H", H > 0)
#   back      Back: the keyboard put away ("IME 0"), the catcher keeping the focus
#   behind    the app sent behind (Home) and brought back: the host's word as the window takes the focus again, once
#             that and the keyboard's window are told ("IME owed: none": no show asked again, Host.java), the keyboard
#             still away (no "IME H" with H > 0 since, the input method service's mInputShown false)
#   cold      the app stopped and launched again: up again with nothing typed
# Each fails on the app's end or its line not there (each waited for, 60 s at most for a run that hangs); the logs in
# out/android/keyboard/CASE.log. Exit 0 when every case passed.
set -u
D="$(cd "$(dirname "$0")" && pwd)"
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
ADB=$SDK/platform-tools/adb
SERIAL=emulator-${EMU_PORT:-5580}
APP_ID=${MBUI_APP_ID:-dev.mbui.demo}
O=out/android/keyboard
rm -rf $O && mkdir -p $O
END='Fatal signal .*\(dev\.mbui|Process: dev\.mbui|JNI DETECTED'
failed=0

# the app's log, the activity manager's events and ImeTracker's from now, into $O/$1.log (logcat's process: $LC)
log_from_now() {
  [ -n "${LC:-}" ] && { kill $LC 2>/dev/null; wait $LC 2>/dev/null; }
  $ADB -s $SERIAL logcat -b all -c
  $ADB -s $SERIAL logcat -b main,system,crash,events -v brief > $O/$1.log 2>&1 &
  LC=$!
}

# until a line matching $2 (or the app's end) is on $1's log: that line, or nothing
wait_line() {
  python3 "$D/logwait.py" --log $O/$1.log --line "$2|$END" --deadline 60
}

pass() { echo "PASS $1${2:+ ($2)}"; }
fail() {
  echo "FAIL $1: $2"
  grep -a -E 'I/mbui .*IME |ImeTracker.*dev\.mbui' $O/$1.log | tail -6
  # (where the keyboard's window is and what the system says it covers: a keyboard shown that the app's insets say
  # nothing of, apart from one never shown)
  $ADB -s $SERIAL shell dumpsys input_method | grep -a -E 'mInputShown|mShowRequested|mCurMethodId|mIsInputViewShown' | head -6
  $ADB -s $SERIAL shell dumpsys window windows | grep -a -A4 'Window{.*InputMethod' | grep -a -E 'InputMethod|mFrame|mHasSurface|isVisible|mViewVisibility' | head -8
  $ADB -s $SERIAL shell dumpsys window | grep -a -E 'InsetsSource .*ime|type=ime' | head -4
  failed=1
}

# (the emulator's setting put back as it was at the end: others use this emulator too)
HARD=$($ADB -s $SERIAL shell settings get secure show_ime_with_hard_keyboard | tr -d '\r')
put_back() {
  if [ "$HARD" = null ]; then $ADB -s $SERIAL shell settings delete secure show_ime_with_hard_keyboard >/dev/null
  else $ADB -s $SERIAL shell settings put secure show_ime_with_hard_keyboard "$HARD"; fi
  [ -n "${LC:-}" ] && kill $LC 2>/dev/null
}
trap put_back EXIT
$ADB -s $SERIAL shell settings put secure show_ime_with_hard_keyboard 1

up() {
  local l
  l=$(wait_line $1 'I/mbui .*: IME [1-9]')
  case "$l" in
    *"IME "[1-9]*) pass $1 "${l##*: }" ;;
    *) fail $1 "the keyboard not up with nothing typed${l:+: $l}" ;;
  esac
}

log_from_now up
"$D/android.sh" run >/dev/null
up up

log_from_now back
$ADB -s $SERIAL shell input keyevent KEYCODE_BACK
l=$(wait_line back 'I/mbui .*: IME 0$')
case "$l" in
  *"IME 0") pass back ;;
  *) fail back "the keyboard not put away${l:+: $l}" ;;
esac

log_from_now behind
$ADB -s $SERIAL shell input keyevent KEYCODE_HOME
wait_line behind 'wm_on_stop_called.*dev\.mbui\.MainActivity' >/dev/null
log_from_now behind
$ADB -s $SERIAL shell am start -n $APP_ID/dev.mbui.MainActivity >/dev/null
l=$(wait_line behind 'I/mbui .*: IME owed: ')
shown=$($ADB -s $SERIAL shell dumpsys input_method | grep -a -m1 -o 'mInputShown=[a-z]*')
up_since=$(grep -a -E 'I/mbui .*: IME [1-9]' $O/behind.log | tail -1)
case "$l" in
  *"IME owed: none")
    if [ "$shown" = mInputShown=false ] && [ -z "$up_since" ]; then pass behind; else
      fail behind "the keyboard up again ($shown${up_since:+, $up_since})"; fi ;;
  *) fail behind "the host's word as the window took the focus: ${l:-none}" ;;
esac

log_from_now cold
$ADB -s $SERIAL shell am force-stop $APP_ID
"$D/android.sh" run >/dev/null
up cold

exit $failed
