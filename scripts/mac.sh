#!/bin/bash
# Build the macOS app and run it. MODE=release|debug, APP=demo|photos|books|stillfail|sffix (only that
# app is built), then:
#   scripts/mac.sh build | run [env...] | script ime | bench | shot | login
# MBUI_CORE=1: the app with the still.fail core in it (src/coredemo: the shell's .a and JavaScriptCore linked in, the
# core's script from out/core/core.js; scripts/core.sh shell + bundle make them). Without it, only src/demo is built:
# the default app stays lean (the shell is some 57 MB stripped). APP=stillfail (still.fail in mbui, src/stillfail) has
# the core in it the same way; APP=sffix is its Home over made-up chats, with no core.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
# MBUI_APP_MOD: an app of a module outside this repository (its moon.work naming mbui; scripts/android.sh says more)
ROOT=$(cd "$D/.." && pwd)
cd "${MBUI_APP_MOD:-$ROOT}"
MODE=${MODE:-release}
FLAG=""; [ "$MODE" = release ] && FLAG=--release
PKG=${APP:-demo}
# login: the core demo signing in the way a command-line tool does (MBUI_AUTH_LOGIN, src/coredemo): what a station's
# remote login runs on this machine. MBUI_CORE_DATA says whose sign-in it is.
[ "${1:-}" = login ] && MBUI_CORE=1
[ "${MBUI_CORE:-0}" != 0 ] && PKG=coredemo
if [ $PKG = coredemo ] || [ $PKG = stillfail ]; then
  [ -f out/core/aarch64-apple-darwin/libstillfail_shell.a ] || "$D/core.sh" shell
  [ -f out/core/core.js ] || "$D/core.sh" bundle
  export MB_CORE_BUNDLE=${MB_CORE_BUNDLE:-$PWD/out/core/core.js}
fi
EXE=$(pkg_build $PKG native $MODE)/$PKG.exe
# the photos app shows made-up pictures from out/pictures (src/photos/pictures_native.mbt)
[ $PKG = photos ] && [ "${1:-build}" != build ] && gallery_pictures
case "${1:-build}" in
  build)
    # moon's build, with the C that moonc generates split and compiled in parallel (scripts/mbc.py: a `cc` first on
    # PATH that moon uses for every C step, all but that one passed through; MBC_SPLIT=0 compiles it whole)
    rm -f out/mbc.log
    PATH="$(python3 "$D/mbc.py" shim "$PWD/out/mbc/bin"):$PATH" MBC_LOG=$PWD/out/mbc.log \
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
  login)
    MBUI_AUTH_LOGIN=1 exec ./$EXE ;;
esac
