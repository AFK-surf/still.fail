#!/bin/bash
# Build the macOS app and run it. MODE=release|debug, then:
#   scripts/mac.sh build | run [env...] | script ime | bench | shot
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
MODE=${MODE:-release}
FLAG=""; [ "$MODE" = release ] && FLAG=--release
EXE=_build/native/$MODE/build/demo/demo.exe
case "${1:-build}" in
  build)
    /usr/bin/time -p moon build --target native $FLAG 2>&1 | python3 "$D/errs.py"
    ls -la $EXE ;;
  script)
    mkdir -p out/$2
    MBUI_SCRIPT=$2 MBUI_SHOT_DIR=$PWD/out/$2 ./$EXE ;;
  shot)
    mkdir -p out/shot
    MBUI_SCRIPT=shot MBUI_SHOT_DIR=$PWD/out/shot ./$EXE ;;
  bench)
    MBUI_BENCH=1 ./$EXE ;;
esac
