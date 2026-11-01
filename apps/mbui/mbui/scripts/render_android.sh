#!/bin/bash
# mbui-render (src/render) on Android: a Tester's draw list (scripts/render_dl.sh) drawn offscreen by the app's GL
# renderer (android_host.c mb_render_init_offscreen: a framebuffer of its own, the text at the list's scale) in an
# emulator, twice (the app started anew each time): the pictures, the same to the byte, and the machine.
#   scripts/render_android.sh build      the draw list and the APK (APP=render, ABI x86_64 unless said)
#   scripts/render_android.sh run        on the emulator adb sees: out/render/{controls-1,controls-2,controls}.png,
#                                        machine.txt
#   scripts/render_android.sh against    out/render/controls.png against goldens/render/android-controls.png, on the
#                                        machine they were made on (goldens/render/android.txt)
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
. "$D/render_dl.sh"
cd "$D/.."
O=out/render
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
ADB=${ADB:-$SDK/platform-tools/adb}
APP_ID=dev.mbui.demo
APK=android/app/build/outputs/apk/debug/app-debug.apk
case "${1:-run}" in
  build)
    rm -rf $O
    render_dl $O/controls.dl
    # render_stub.c (src/render's own C) among libmbui.so's: what scripts/android.sh takes from a hook
    ABI=${ABI:-x86_64} APP=render MBUI_ANDROID_HOOK=$D/render_android_hook.sh bash "$D/android.sh" build
    ;;
  run)
    $ADB install -r $APK >/dev/null
    render_uid=$($ADB shell pm list packages -U $APP_ID | tr -d '\r' | sed -n "s/^package:$APP_ID uid:\([0-9]*\)$/\1/p")
    case "$render_uid" in ""|*[!0-9]*) echo "render_android: the app has no installed uid" >&2; exit 1 ;; esac
    # the screen on and unlocked: the app's surface (and with it its GL thread, where mbui-render runs) is made
    $ADB shell input keyevent KEYCODE_WAKEUP
    $ADB shell wm dismiss-keyguard
    F=/data/user/0/$APP_ID/files
    # draw list $O/$1.dl drawn by the app into $2
    draw() {
      $ADB shell am force-stop $APP_ID
      $ADB shell run-as $APP_ID mkdir -p files
      $ADB shell run-as $APP_ID rm -f files/$1.png
      $ADB exec-in "run-as $APP_ID sh -c 'cat > files/$1.dl'" < $O/$1.dl
      $ADB logcat -c
      $ADB shell am start -n $APP_ID/dev.mbui.MainActivity --es env "'MBUI_DL=$F/$1.dl;MBUI_DL_PNG=$F/$1.png'" >/dev/null
      # Only this renderer's completion or crash; a system app's crash says nothing about this picture.
      said=$($ADB logcat --uid="$render_uid" -v brief -e 'mbui-render: |FATAL EXCEPTION|Fatal signal' -m 1 | grep -v '^-----')
      echo "$1: $said"
      case "$said" in
        *"mbui-render: "*"instances"*) ;;
        *) $ADB logcat -d -t 200 | tail -60; exit 1 ;;
      esac
      $ADB exec-out run-as $APP_ID cat files/$1.png > $2
    }
    for n in 1 2; do
      draw controls $O/controls-$n.png
    done
    # lines drawn as they are (no reference: checked)
    draw lines $O/lines.png
    "$D/chk" lines $O/lines.png
    draw shapes $O/shapes.png
    "$D/chk" shapes $O/shapes.png
    draw contained $O/contained.png
    "$D/chk" contained $O/contained.png
    for k in matte-fill matte-fill-reference matte-contain matte-contain-reference matte-inset matte-inset-reference; do
      draw "$k" "$O/$k.png"
    done
    render_matte android
    # partial-b drawn only where it differs from partial-a, and whole (render_partial)
    $ADB shell am force-stop $APP_ID
    $ADB shell run-as $APP_ID rm -f files/partial.png files/partial.whole.png
    for k in partial-a partial-b; do $ADB exec-in "run-as $APP_ID sh -c 'cat > files/$k.dl'" < $O/$k.dl; done
    $ADB logcat -c
    $ADB shell am start -n $APP_ID/dev.mbui.MainActivity \
      --es env "'MBUI_DL_FROM=$F/partial-a.dl;MBUI_DL=$F/partial-b.dl;MBUI_DL_PNG=$F/partial.png'" >/dev/null
    said=$($ADB logcat --uid="$render_uid" -v brief -e 'mbui-render: .*(drawn in parts|not written|another window)|FATAL EXCEPTION|Fatal signal' -m 1 | grep -v '^-----')
    echo "partial: $said"
    case "$said" in
      *"drawn in parts"*) ;;
      *) $ADB logcat -d -t 200 | tail -60; exit 1 ;;
    esac
    $ADB exec-out run-as $APP_ID cat files/partial.png > $O/partial.png
    $ADB exec-out run-as $APP_ID cat files/partial.whole.png > $O/partial.whole.png
    render_partial android
    $ADB shell am force-stop $APP_ID
    md5sum $O/controls-1.png $O/controls-2.png
    if ! cmp -s $O/controls-1.png $O/controls-2.png; then
      echo "render_android: the two runs' pictures differ"
      exit 1
    fi
    cp $O/controls-1.png $O/controls.png
    img=$(ls -d $SDK/system-images/*/*/x86_64 2>/dev/null | head -1)
    {
      echo "draw list $(md5sum < $O/controls.dl | cut -c1-32)"
      echo "picture $(md5sum < $O/controls.png | cut -c1-32)"
      echo "image ${ImageOS:-} ${ImageVersion:-}"
      echo "emulator $(sed -n 's/^Pkg.Revision=//p' $SDK/emulator/source.properties)"
      echo "system $(echo "$img" | sed "s|$SDK/system-images/||") $(sed -n 's/^Pkg.Revision=//p' "$img/source.properties" 2>/dev/null)"
      echo "build $($ADB shell getprop ro.build.fingerprint | tr -d '\r')"
      echo "gl $($ADB shell dumpsys SurfaceFlinger | sed -n 's/^GLES: //p' | head -1 | tr -d '\r')"
      echo "cpu $(sed -n 's/^model name\t: //p' /proc/cpuinfo | head -1)"
    } | tee $O/machine.txt
    ;;
  against)
    render_against android "emulator system build"
    ;;
esac
