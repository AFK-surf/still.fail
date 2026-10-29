#!/bin/bash
# still.fail's scenes on a phone (scripts/appbench.sh's, the phone's own screen): sffix's made-up chats in a debug
# build of its own (fail.still.android.dev, beside the apps the phone has), each scene's script run on the phone
# (MBUI_DRIVE_B64), each frame it draws said on its log (MBUI_PROBE_FRAMES=1: PERF lines), read back into the same
# table as offscreen (src/sfbench, MBUI_BENCH_LOG). Three steps, where each can run:
#   scripts/appbench_phone.sh build            (a Mac with the Android SDK) out/bench/sffix-debug.apk
#   SERIAL=… scripts/appbench_phone.sh run     (where the phone's adb is) installed, every scene run: out/bench/phone-<scene>.log
#   scripts/appbench_phone.sh sum              (a Mac) the table, kept in bench/app-history.jsonl (COMMIT, LABEL)
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D/.."
mkdir -p out/bench bench
# scene      fixture (小屏's on a phone's screen, medium on an opened fold's inner one)
scenes="idle-small chat-long
fling chat-long
backswipe chat
newchat home
medium chat"
case "${1:-}" in
  build)
    . "$D/env.sh"
    APP=sffix VARIANT=debug MODE=release bash scripts/android.sh build || exit 1
    cp android/app/build/outputs/apk/debug/app-debug.apk out/bench/sffix-debug.apk && ls -la out/bench/sffix-debug.apk
    ;;
  run)
    ADB=${ADB:-adb}
    S=${SERIAL:?SERIAL: the phone adb reaches}
    PKG=fail.still.android.dev
    if [ "${INSTALL:-1}" = 1 ]; then
      # (in pieces: a large push over a shared phone's adb stalls)
      $ADB -s $S shell rm -f /data/local/tmp/zz_bench.apk
      rm -rf out/bench/apk.parts && mkdir -p out/bench/apk.parts
      split -b 2m out/bench/sffix-debug.apk out/bench/apk.parts/part_
      for p in out/bench/apk.parts/part_*; do
        $ADB -s $S push "$p" /data/local/tmp/zz_part >/dev/null || exit 1
        $ADB -s $S shell "cat /data/local/tmp/zz_part >> /data/local/tmp/zz_bench.apk"
      done
      $ADB -s $S shell pm install -r -t /data/local/tmp/zz_bench.apk || exit 1
    fi
    # (adb's stdin its own: else it reads the scenes' list away)
    while read -r scene fixture <&3; do
      [ -n "${SCENES:-}" ] && ! echo " $SCENES " | grep -q " $scene " && continue
      # (what the system says is the phone's own: a script's `system` steps are a Tester's)
      script=$(grep -v '^system ' scripts/bench/$scene.drive | base64 | tr -d '\n')
      $ADB -s $S shell am force-stop $PKG
      $ADB -s $S logcat -c
      $ADB -s $S shell am start -n $PKG/dev.mbui.MainActivity --es env "'MBUI_FIXTURE=$fixture;MBUI_PROBE_FRAMES=1;MBUI_DRIVE_B64=$script'" >/dev/null
      # (the run's end, as its log says it: DRIVE PASS, or DRIVE END with what it failed with, within its own timeout)
      $ADB -s $S logcat -m 1 -e "DRIVE (PASS|END)" >/dev/null
      $ADB -s $S logcat -d | grep -E "PERF |DRIVE " > out/bench/phone-$scene.log
      echo "$scene: $(grep -c 'PERF ' out/bench/phone-$scene.log) frames said, $(grep -E 'DRIVE (PASS|FAIL|END)' out/bench/phone-$scene.log | head -2 | tr '\n' ' ')"
    done 3<<< "$scenes"
    $ADB -s $S shell am force-stop $PKG
    ;;
  sum)
    . "$D/env.sh"
    APP=sfbench MODE=release bash scripts/mac.sh build >/dev/null || exit 1
    exe=./_build/native/release/build/stillfail/sfbench/sfbench.exe
    commit=${COMMIT:-$(git rev-parse --short HEAD 2>/dev/null)}
    echo "commit $commit ${LABEL:+($LABEL)}, a phone"
    echo "| scene | frames in seconds | work ms in all | work ms med / p95 | build | layout | paint | present | GPU | nodes | laid anew | instances | redrawn area | upload KB |"
    echo "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"
    lines=()
    while read -r scene fixture; do
      [ -f out/bench/phone-$scene.log ] || continue
      out=$(MBUI_BENCH_NAME=$scene MBUI_BENCH_LOG="$PWD/out/bench/phone-$scene.log" "$exe" 2>&1)
      echo "$out" | grep '^APPROW ' | cut -c8-
      lines+=("$(echo "$out" | grep '^APPBENCH ' | cut -c10-)")
    done <<< "$scenes"
    {
      printf '{"time": %s, "commit": "%s", "label": "%s", "host": "phone", "scenes": [' "$(date +%s)" "$commit" "${LABEL:-}"
      first=1
      for l in "${lines[@]}"; do [ -z "$l" ] && continue; [ $first = 1 ] || printf ', '; printf '%s' "$l"; first=0; done
      printf ']}\n'
    } >> bench/app-history.jsonl
    ;;
  *) echo "appbench_phone.sh build | run | sum"; exit 2 ;;
esac
