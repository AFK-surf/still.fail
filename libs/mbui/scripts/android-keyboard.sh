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
#   split     (SPLIT=1, a local emulator check only) a field tapped in split screen: the keyboard is shown by the
#             system even though its insets control target is remote; Back and another tap show it again
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
  local name=$1
  shift
  [ -n "${LC:-}" ] && { kill $LC 2>/dev/null; wait $LC 2>/dev/null; }
  $ADB -s $SERIAL logcat -b all -c
  if [ $# -gt 0 ]; then
    $ADB -s $SERIAL logcat -b main,system -v brief -s "$@" > $O/$name.log 2>&1 &
  else
    $ADB -s $SERIAL logcat -b main,system,crash,events -v brief > $O/$name.log 2>&1 &
  fi
  LC=$!
}

# until a line matching $2 (or the app's end) is on $1's log: that line, or nothing
wait_line() {
  "$D/chk" logwait --log $O/$1.log --line "$2|$END" --deadline 60
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
  [ "${split_started:-0}" != 1 ] || $ADB -s $SERIAL shell am force-stop "$APP_ID" >/dev/null
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

if [ "${SPLIT:-0}" = 1 ]; then
  # A real field, initially unfocused: moving a key catcher with its keyboard already up into split screen would not
  # exercise the host's request in split screen. The other stage is Settings, started before returning to the demo.
  log_from_now split-ready
  ENV=MBUI_KEYBOARD_FIELD=1 "$D/android.sh" run >/dev/null
  ready=$(wait_line split-ready 'I/mbui .*: FIELD ready')
  if [[ "$ready" != *"FIELD ready"* ]]; then
    fail split-ready "the input field did not start${ready:+: $ready}"
  else
    $ADB -s $SERIAL shell am start -W -a android.settings.SETTINGS >/dev/null
    $ADB -s $SERIAL shell am start -W -n "$APP_ID/dev.mbui.MainActivity" >/dev/null
    task=$($ADB -s $SERIAL shell am stack list | sed -n "s/.*taskId=\([0-9][0-9]*\): $APP_ID\/dev\.mbui\.MainActivity.*/\1/p" | head -1 | tr -d '\r')
    if [ -z "$task" ]; then
      fail split-ready "the demo has no task"
    else
      split_started=1
      # The task bounds change before the transition's snapshot stops blocking touches. Wait for this enter
      # transition's own WindowManager completion, not a guessed delay or a tap during the animation.
      log_from_now split-transition ShellSplitScreen:D WindowManager:V
      $ADB -s $SERIAL shell dumpsys activity service SystemUIService WMShell splitscreen moveToSideStage "$task" 1 >/dev/null
      entering=$("$D/chk" logwait --log $O/split-transition.log --line 'playAnimation: transition=[0-9]+' --deadline 60)
      transition=$(printf '%s\n' "$entering" | sed -n 's/.*transition=\([0-9][0-9]*\).*/\1/p')
      if [ -n "$transition" ]; then
        finished=$("$D/chk" logwait --log $O/split-transition.log --line "Finish Transition .#$transition." --deadline 60)
      else
        finished=
      fi
      if [[ "$finished" != *"Finish Transition"* ]]; then
        fail split-transition "the split enter transition did not finish${entering:+: $entering}"
      else
        stack=$($ADB -s $SERIAL shell am stack list)
        bounds=$(printf '%s\n' "$stack" | sed -n "s/.*taskId=$task: $APP_ID\/dev\.mbui\.MainActivity bounds=\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\].*/\1 \2 \3 \4/p" | head -1)
        size=$($ADB -s $SERIAL shell wm size | sed -n 's/.*size: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1 | tr -d '\r')
        if [ -z "$bounds" ] || [ -z "$size" ]; then
          fail split-ready "could not read the demo's split bounds"
        else
          read -r left top right bottom <<< "$bounds"
          read -r screen_w screen_h <<< "$size"
          if [ "$((right-left))" -ge "$screen_w" ] && [ "$((bottom-top))" -ge "$screen_h" ]; then
            fail split-ready "the demo did not enter split screen ($bounds)"
          else
            density=$($ADB -s $SERIAL shell wm density | sed -n 's/.*density: \([0-9]*\).*/\1/p' | tail -1 | tr -d '\r')
            x=$(((left+right)/2))
            y=$((top + 32 * ${density:-160} / 160))
            log_from_now split
            $ADB -s $SERIAL shell input tap "$x" "$y"
            focused=$(wait_line split 'I/mbui .*: FIELD focused')
            if [[ "$focused" != *"FIELD focused"* ]]; then
              fail split "the field did not take focus${focused:+: $focused}"
            else
              up split
              target=$($ADB -s $SERIAL shell dumpsys window | grep -a -m1 'imeControlTarget in display')
              shown=$($ADB -s $SERIAL shell dumpsys input_method | grep -a -m1 -o 'mInputShown=[a-z]*')
              if [[ "$target" != *RemoteInsetsControlTarget* ]] || [ "$shown" != mInputShown=true ]; then
                fail split "the system did not show the keyboard with remote insets control ($shown; $target)"
              else
                pass split-system "$shown, remote insets control"
              fi
              log_from_now split-back
              $ADB -s $SERIAL shell input keyevent KEYCODE_BACK
              l=$(wait_line split-back 'I/mbui .*: IME 0$')
              if [[ "$l" != *"IME 0" ]]; then
                fail split-back "the keyboard did not go down${l:+: $l}"
              else
                pass split-back
                log_from_now split-again
                $ADB -s $SERIAL shell input tap "$x" "$y"
                up split-again
              fi
            fi
          fi
        fi
      fi
    fi
  fi
fi

exit $failed
