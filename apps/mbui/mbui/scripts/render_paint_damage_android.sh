#!/bin/bash
# render_paint_damage.sh's renderer: the existing render APK on the synthetic Android emulator, with the exact
# preceding and current DL supplied by the caller. render_android.sh installs the APK and opens its screen first.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/render_android_device.sh"
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
ADB=${ADB:-$SDK/platform-tools/adb}
render_android_device
APP_ID=dev.mbui.demo
F=/data/user/0/$APP_ID/files
render_uid=$(render_adb shell pm list packages -U $APP_ID | tr -d '\r' | sed -n "s/^package:$APP_ID uid:\([0-9]*\)$/\1/p")
case "$render_uid" in ""|*[!0-9]*) echo "paint damage: the Android renderer has no installed uid" >&2; exit 1 ;; esac
render_adb shell am force-stop $APP_ID
render_adb shell run-as $APP_ID mkdir -p files
render_adb shell run-as $APP_ID rm -f files/paint-before.dl files/paint-after.dl files/paint.png files/paint.whole.png
render_adb exec-in "run-as $APP_ID sh -c 'cat > files/paint-before.dl'" < "$MBUI_DL_FROM"
render_adb exec-in "run-as $APP_ID sh -c 'cat > files/paint-after.dl'" < "$MBUI_DL"
render_adb logcat -c
render_adb shell am start -n $APP_ID/dev.mbui.MainActivity \
  --es env "'MBUI_DL_FROM=$F/paint-before.dl;MBUI_DL=$F/paint-after.dl;MBUI_DL_PNG=$F/paint.png'" >/dev/null
said=$(render_adb logcat --uid="$render_uid" -v brief \
  -e 'mbui-render: .*(drawn in parts|not written|another window)|FATAL EXCEPTION|Fatal signal' -m 1 | grep -v '^-----')
# Keep all this app's rendering messages, including unknown glyphs, for the caller's checks.
render_adb logcat --uid="$render_uid" -d -v brief
case "$said" in *"drawn in parts"*) ;; *) exit 1 ;; esac
render_adb exec-out run-as $APP_ID cat files/paint.png > "$MBUI_DL_PNG"
render_adb exec-out run-as $APP_ID cat files/paint.whole.png > "${MBUI_DL_PNG%.png}.whole.png"
