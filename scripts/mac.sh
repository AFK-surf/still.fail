#!/bin/bash
# Build the macOS app and run it. MODE=release|debug, then:
#   scripts/mac.sh build | run [env...] | script ime | bench | shot
# MBUI_CORE=1: the app with the still.fail core in it (src/coredemo: the shell's .a and JavaScriptCore linked in, the
# core's script from out/core/core.js; scripts/core.sh shell + bundle make them). Without it, only src/demo is built:
# the default app stays lean (the shell is some 57 MB stripped).
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
MODE=${MODE:-release}
FLAG=""; [ "$MODE" = release ] && FLAG=--release
PKG=demo
if [ "${MBUI_CORE:-0}" != 0 ]; then
  PKG=coredemo
  [ -f out/core/aarch64-apple-darwin/libstillfail_shell.a ] || "$D/core.sh" shell
  [ -f out/core/core.js ] || "$D/core.sh" bundle
  export MB_CORE_BUNDLE=${MB_CORE_BUNDLE:-$PWD/out/core/core.js}
fi
EXE=_build/native/$MODE/build/$PKG/$PKG.exe
case "${1:-build}" in
  build)
    /usr/bin/time -p moon build --target native $FLAG src/$PKG 2>&1 | python3 "$D/errs.py"
    ls -la $EXE ;;
  run)
    ./$EXE ;;
  script)
    mkdir -p out/$2
    MBUI_SCRIPT=$2 MBUI_SHOT_DIR=$PWD/out/$2 ./$EXE ;;
  shot)
    mkdir -p out/shot
    MBUI_SCRIPT=shot MBUI_SHOT_DIR=$PWD/out/shot ./$EXE ;;
  bench)
    MBUI_BENCH=1 ./$EXE ;;
esac
