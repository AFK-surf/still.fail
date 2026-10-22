#!/bin/bash
# Build the macOS app and run it. MODE=release|debug, APP=demo|textdiff|bench (only that app is built; an app of a module
# outside mbui: MBUI_APP_MOD, still.fail's apps/mbui), then:
#   scripts/mac.sh build | run [env...] | script ime | bench | shot
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
# MBUI_APP_MOD: an app of a module outside this repository (its moon.work naming mbui; scripts/android.sh says more)
ROOT=$(cd "$D/.." && pwd)
cd "${MBUI_APP_MOD:-$ROOT}"
MODE=${MODE:-release}
FLAG=""; [ "$MODE" = release ] && FLAG=--release
PKG=${APP:-demo}
EXE=$(pkg_build $PKG native $MODE)/$PKG.exe
# the photos app (still.fail's apps/mbui) shows made-up pictures from out/pictures (src/photos/pictures_native.mbt)
[ $PKG = photos ] && [ "${1:-build}" != build ] && gallery_pictures
case "${1:-build}" in
  build)
    # moon's build, with the C that moonc generates split and compiled in parallel (scripts/mbc: a `cc` first on
    # PATH that moon uses for every C step, all but that one passed through; MBC_SPLIT=0 compiles it whole)
    rm -f out/mbc.log
    PATH="$("$D/mbc" shim "$PWD/out/mbc/bin"):$PATH" MBC_LOG=$PWD/out/mbc.log \
      /usr/bin/time -p moon build --target native $FLAG src/$PKG 2>&1 | python3 "$D/errs.py"
    cat out/mbc.log 2>/dev/null || true
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
