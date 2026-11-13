#!/bin/bash
# Flutter's twin of the hill-climb: bench/flutter (the five scenes of
# src/bench, after nanoui's hillclimb/, as ordinary Flutter widgets), built
# AOT for macOS desktop (Impeller on Metal) and run in a 900×640 window in
# the bottom-left corner that never takes focus (bench/flutter/macos).
#   scripts/bench_flutter.sh [run]   build, run, append to bench/history.jsonl ("fw": "flutter"), compare
#   scripts/bench_flutter.sh build   only build
#   scripts/bench_flutter.sh size    build Flutter's counter template (release) and print its sizes
# MODE=release (default) or profile. Frames follow the display's vsync;
# HEAT=1 keeps one other core busy meanwhile (a shell loop, not in the app),
# so the CPU stays clocked up as it does under mbui's and nanoui's
# back-to-back loops: at 60 Hz with nothing else running, macOS clocks the
# cores down between frames and the same frame takes several times longer.
# PACE=hot draws frames back to back instead (the engine's warm-up frame
# path, no vsync; the engine then rasterizes only a few of them). FLUTTER:
# the flutter command (default: flutter on PATH).
# LABEL, SCENES (also scroll_jump, list_jump), FRAMES, REPEAT as for
# scripts/bench.sh; QUIET=0 skips waiting for a quiet machine; HISTORY=file
# appends somewhere else than bench/history.jsonl.
# Only bench/flutter's sources are kept in git: the rest of the macOS runner
# is made by `flutter create` in _build/flutter-bench, with Impeller on, the
# app an agent (LSUIElement: no Dock icon, not activated) and the sandbox off
# (so it can append to bench/history.jsonl).
set -e
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D/.."
FLUTTER=${FLUTTER:-flutter}
MODE=${MODE:-release}
B=_build/flutter-bench
Mode=$(echo "${MODE:0:1}" | tr a-z A-Z)${MODE:1}
APP=$B/build/macos/Build/Products/$Mode/mbui_bench.app
P=/usr/libexec/PlistBuddy

create() { # dir name
  if [ ! -f "$1/macos/Runner.xcodeproj/project.pbxproj" ]; then
    rm -rf "$1" && mkdir -p "$1"
    (cd "$1" && $FLUTTER create --platforms=macos --project-name "$2" . >/dev/null)
    rm -rf "$1/test" "$1/analysis_options.yaml"
  fi
}
build() {
  if [ ! -f $B/macos/Runner.xcodeproj/project.pbxproj ]; then
    create $B mbui_bench
    $P -c 'Add :FLTEnableImpeller bool true' -c 'Add :LSUIElement bool true' $B/macos/Runner/Info.plist
    for e in DebugProfile Release; do
      $P -c 'Set :com.apple.security.app-sandbox false' $B/macos/Runner/$e.entitlements
    done
  fi
  rsync -a --exclude .dart_tool --exclude build --exclude pubspec.lock bench/flutter/ $B/
  (cd $B && $FLUTTER build macos --$MODE 2>&1 | grep -v '^$')
  [ -x "$APP/Contents/MacOS/mbui_bench" ]
}
quiet() {
  [ "${QUIET:-1}" = 0 ] || bash "$D/bench_quiet.sh"
}
run() {
  # The Dart side exits when done; a watchdog ends it if frames stop.
  heater=
  if [ "${HEAT:-0}" = 1 ]; then
    (while :; do :; done) >/dev/null 2>&1 </dev/null &
    heater=$!
  fi
  BENCH_HEAT="${HEAT:-0}" BENCH_LABEL="${LABEL:-}" BENCH_SCENES="${SCENES:-}" BENCH_FRAMES="${FRAMES:-}" BENCH_REPEAT="${REPEAT:-}" \
    BENCH_PACE="${PACE:-}" BENCH_HISTORY="$PWD/${HISTORY:-bench/history.jsonl}" "$APP/Contents/MacOS/mbui_bench" &
  pid=$!
  (sleep "${TIMEOUT:-900}" && kill $pid) >/dev/null 2>&1 </dev/null &
  dog=$!
  status=0
  wait $pid || status=$?
  pkill -P $dog 2>/dev/null; kill $dog 2>/dev/null || true
  [ -z "$heater" ] || kill $heater 2>/dev/null || true
  return $status
}
compare() {
  python3 "$D/bench_compare.py" ${HISTORY:-bench/history.jsonl} ${NANOUI:+"$NANOUI/hillclimb/history.jsonl"}
}
sizes() { # app
  local app=$1 total=0
  total=$(find "$app" -type f -exec stat -f %z {} + | awk '{s+=$1} END{print s}')
  echo "$app: $total bytes in all ($(du -sk "$app" | cut -f1) KB on disk)"
  find "$app" -type f -size +20k -exec stat -f '%z %N' {} + | sort -rn | while read -r n f; do
    arch=$(lipo -archs "$f" 2>/dev/null || true)
    if [ -n "$arch" ] && [ "$arch" != arm64 ]; then
      lipo -thin arm64 "$f" -output /tmp/bench_flutter_slice 2>/dev/null &&
        arch="$arch; arm64 slice $(stat -f %z /tmp/bench_flutter_slice)"
    fi
    echo "  $n  ${f#$app/}${arch:+  ($arch)}"
  done
  rm -f /tmp/bench_flutter_slice
}
size() {
  C=_build/flutter-counter
  create $C counter
  (cd $C && $FLUTTER build macos --release 2>&1 | grep -v '^$')
  sizes $C/build/macos/Build/Products/Release/counter.app
  [ -d $B/build/macos/Build/Products/Release/mbui_bench.app ] && sizes $B/build/macos/Build/Products/Release/mbui_bench.app
  true
}
case "${1:-run}" in
  build) build ;;
  run) build && quiet && run && compare ;;
  size) size ;;
  compare) compare ;;
esac
