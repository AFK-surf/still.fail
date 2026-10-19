#!/bin/bash
# Build the Windows app and run it, in Git Bash on Windows with MoonBit and
# MSVC (cl.exe from a Developer Command Prompt, or set MOON_CC=clang-cl.exe).
#   MODE=release|debug APP=demo|photos scripts/win.sh build | run | script ime|photos | shot | bench
# moon.pkg cannot choose native stubs per OS, so the build runs on a copy of
# the module in out/win/mod whose host lists the win_* stubs, whose apps link
# no Apple frameworks (the Windows libraries come from #pragma comment), and
# where photos shows src/photos/pictures/windows.mbt.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
MODE=${MODE:-release}
FLAG=""; [ "$MODE" = release ] && FLAG=--release
PKG=${APP:-demo}
M=out/win/mod
EXE=$M/_build/native/$MODE/build/$PKG/$PKG.exe

sync() {
  mkdir -p $M/src
  cp -p moon.mod $M/
  # exactly src/: a file gone from it goes from the copy too (then the copy's own files, after; Git Bash has no rsync)
  if command -v rsync >/dev/null; then rsync -a --delete src/ $M/src/; else rm -rf $M/src && cp -rp src $M/src; fi
  sed -e 's/"native-stub": *\[[^]]*\]/"native-stub": [ "win_app.c", "win_render.cpp", "win_text.cpp", "win_image.cpp" ]/' \
      -e 's/-fobjc-arc *//' src/host/moon.pkg > $M/src/host/moon.pkg
  # every app (demo, photos…) links no Apple frameworks
  for p in src/*/moon.pkg; do
    grep -q '"is-main"' $p && sed -e '/"cc-link-flags"/d' $p > $M/$p
  done
  cp -p src/photos/pictures/windows.mbt $M/src/photos/pictures_native.mbt
  # the core (pthreads, dispatch, JavaScriptCore) isn't built for Windows yet
  rm -rf $M/src/coredemo $M/src/stillfail
  if ! grep -q win_app.c $M/src/host/moon.pkg || grep -q -e -framework -e '\.m"' $M/src/*/moon.pkg; then
    echo "win.sh: src/host/moon.pkg or an app's moon.pkg no longer has the expected shape" >&2
    exit 1
  fi
}

shot_dir() {
  rm -rf "$1"; mkdir -p "$1"
  cygpath -w "$PWD/$1"
}

case "${1:-build}" in
  build)
    sync
    # moon's build, with the C that moonc generates split and compiled by cl in parallel, moonbit_init at /O1
    # (scripts/mbc.py: a cl.exe first on PATH, every other command passed to the real one; MBC_SPLIT=0 compiles it
    # whole). Windows' python is `python`.
    PY=$(command -v python || command -v python3)
    SHIM=$(cygpath -u "$("$PY" "$D/mbc.py" shim "$(cygpath -w "$PWD/out/mbc/win")" | tr -d '\r')")
    rm -f out/mbc.log
    LOG=$(cygpath -w "$PWD/out/mbc.log")
    code=0
    (cd $M && export PATH="$SHIM:$PATH" MBC_LOG="$LOG" MBC_VERBOSE=1 && time moon build --target native $FLAG src/$PKG) || code=$?
    cat out/mbc.log 2>/dev/null || echo "win.sh: moon ran no command through scripts/mbc.py (out/mbc/win)"
    [ $code = 0 ] || exit $code
    ls -la $EXE ;;
  run)
    ./$EXE ;;
  script)
    MBUI_SCRIPT=$2 MBUI_SHOT_DIR="$(shot_dir out/$2)" ./$EXE ;;
  shot)
    MBUI_BENCH=${MBUI_BENCH:--1} MBUI_SCRIPT=shot MBUI_SHOT_DIR="$(shot_dir out/shot-win)" ./$EXE ;;
  bench)
    MBUI_BENCH=1 ./$EXE ;;
esac
