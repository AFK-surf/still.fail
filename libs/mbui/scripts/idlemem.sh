#!/bin/bash
# An app's memory once idle (MyGo's internal/idlemem's way): started afresh COUNT times (3), each signed out on data of
# its own, measured IDLE seconds after it started (8), and the medians printed as JSON in bytes. A measurement, not a
# test: it is taken at that moment and waits for nothing else (the trend's: .github/workflows/mbui-size.yml).
#   mac:     the physical footprint (Activity Monitor's Memory) of the app's process ("app") and of it with the processes
#            it started ("total")                                   scripts/idlemem.sh mac APP.app|ZIP
#   android: the proportional set size (dumpsys meminfo's TOTAL PSS) of the app's process ("app"), and its Java heap's
#            and native heap's parts, on the device adb is given (ANDROID_SERIAL; an emulator of its own:
#            AVD=mbui-idlemem EMU_PORT=5592 scripts/android.sh emu)  scripts/idlemem.sh android APK
#            ("native" is dumpsys's Native Heap, the system allocator's alone. Since 2026-11-11 MoonBit's runtime
#            allocates with mimalloc (mbui's scripts/android.sh), whose memory dumpsys counts elsewhere: "native" fell
#            by what moved out of it, and only "app" compares a build from before with one after.)
set -eo pipefail
P=${MBUI_SIZE_PREFIX:-}
COUNT=${COUNT:-3}
IDLE=${IDLE:-8}
kind=${1:-} what=${2:-}
[ -e "$what" ] || { echo "idlemem.sh mac APP.app|ZIP | android APK" >&2; exit 2; }
median() { sort -n | awk '{v[NR]=$1} END {print (NR%2) ? v[(NR+1)/2] : int((v[NR/2]+v[NR/2+1])/2)}'; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

case $kind in
  mac)
    if [ -f "$what" ]; then
      mkdir -p "$tmp/uz"
      ditto -x -k "$what" "$tmp/uz"
      what=$(find "$tmp/uz" -maxdepth 2 -name '*.app' -not -path '*/__MACOSX/*' | head -1)
    fi
    exe="$what/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$what/Contents/Info.plist")"
    # (a process's phys_footprint, `footprint -f bytes`'s "Footprint: N B")
    fp() { footprint -p "$1" -f bytes --noCategories 2>/dev/null | sed -n 's/.*Footprint: \([0-9]*\) B.*/\1/p' | head -1; }
    tree() { local p; echo "$1"; for p in $(pgrep -P "$1"); do tree "$p"; done; }
    for k in $(seq 1 "$COUNT"); do
      # signed out, on data of its own (its core's files and its keys in files: no Keychain dialog), no station of its own
      mkdir -p "$tmp/$k"
      MBUI_CORE_DATA="$tmp/$k/core" MBUI_KEYS_IN_FILES=1 MBUI_ISOLATED_STATION=1 MBUI_WIN=1280x800 \
        "$exe" > "$tmp/$k/log" 2>&1 &
      pid=$!
      sleep "$IDLE" # det-ok(script-wait): the moment measured at, as MyGo's idlemem; no wait for an event
      kill -0 $pid 2>/dev/null || { echo "idlemem: the app exited after starting:" >&2; tail -20 "$tmp/$k/log" >&2; exit 1; }
      app=$(fp $pid) total=0
      for p in $(tree $pid); do total=$((total + $(fp "$p" || echo 0))); done
      echo "mac run $k: app $app B, with its processes $total B" >&2
      echo "$app" >> "$tmp/app"; echo "$total" >> "$tmp/total"
      pkill -TERM -P $pid 2>/dev/null || true
      kill -TERM $pid; wait $pid 2>/dev/null || true
    done
    printf '{"%smac_idle":{"app":%s,"total":%s}}\n' "$P" "$(median < "$tmp/app")" "$(median < "$tmp/total")"
    ;;
  android)
    SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
    ADB=$SDK/platform-tools/adb
    pkg=$("$(ls -d "$SDK"/build-tools/*/aapt2 | tail -1)" dump packagename "$what")
    "$ADB" install -r "$what" >/dev/null
    act=$("$ADB" shell cmd package resolve-activity --brief "$pkg" | tail -1 | tr -d '\r')
    echo "android: $pkg, $act" >&2
    # (dumpsys meminfo's summary in KB: the row's first number)
    row() { sed -n "s/^ *$1: *\([0-9]*\).*/\1/p" "$2" | head -1; }
    for k in $(seq 1 "$COUNT"); do
      "$ADB" shell am force-stop "$pkg"
      "$ADB" shell pm clear "$pkg" >/dev/null
      "$ADB" shell am start -n "$act" >/dev/null
      sleep "$IDLE" # det-ok(script-wait): the moment measured at, as MyGo's idlemem; no wait for an event
      "$ADB" shell pidof "$pkg" >/dev/null || { echo "idlemem: the app exited after starting" >&2; "$ADB" logcat -d -t 40 >&2; exit 1; }
      "$ADB" shell dumpsys meminfo "$pkg" | tr -d '\r' > "$tmp/m$k"
      pss=$(sed -n 's/^ *TOTAL PSS: *\([0-9]*\).*/\1/p' "$tmp/m$k" | head -1)
      [ -n "$pss" ] || pss=$(sed -n 's/^ *TOTAL *\([0-9]*\).*/\1/p' "$tmp/m$k" | head -1)
      java=$(row "Java Heap" "$tmp/m$k") native=$(row "Native Heap" "$tmp/m$k")
      echo "android run $k: PSS $pss KB (Java $java, native $native)" >&2
      echo $((pss * 1024)) >> "$tmp/pss"; echo $((java * 1024)) >> "$tmp/java"; echo $((native * 1024)) >> "$tmp/native"
    done
    "$ADB" shell am force-stop "$pkg"
    printf '{"%sandroid_idle":{"app":%s,"java":%s,"native":%s}}\n' "$P" "$(median < "$tmp/pss")" "$(median < "$tmp/java")" \
      "$(median < "$tmp/native")"
    ;;
  *) echo "idlemem.sh mac APP.app|ZIP | android APK" >&2; exit 2 ;;
esac
