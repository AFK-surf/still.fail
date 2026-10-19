#!/bin/bash
# Build the Windows app and run it, in Git Bash on Windows with MoonBit and
# MSVC (cl.exe from a Developer Command Prompt, or set MOON_CC=clang-cl.exe).
#   MODE=release|debug APP=demo|photos scripts/win.sh build | run | script ime|photos | shot | bench
# moon.pkg cannot choose native stubs per OS, so the build runs on a copy of
# the module in out/win/mod whose host lists the win_* stubs, whose apps link
# no Apple frameworks (the Windows libraries come from #pragma comment), and
# where photos shows src/photos/pictures/windows.mbt. MBUI_APP_MOD=<a module outside this repository whose
# moon.work names mbui> (still.fail's apps/mbui): its app APP, built from a copy of it in out/win/app whose workspace
# names that copy of mbui instead, its apps linking no Apple frameworks either; a package whose stubs are Apple's own
# (.m: a core host's) takes its win_engine.c in their place where it has one (still.fail's: the core in Hermes on
# Windows), else is left out.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
MODE=${MODE:-release}
FLAG=""; [ "$MODE" = release ] && FLAG=--release
PKG=${APP:-demo}
M=out/win/mod
EXE=$M/_build/native/$MODE/build/$PKG/$PKG.exe
# an app of another module: built in its copy, beside mbui's
APPMOD=${MBUI_APP_MOD:+$(cd "$MBUI_APP_MOD" && pwd)}
AM=out/win/app
if [ -n "$APPMOD" ]; then
  EXE=$AM/_build/native/$MODE/build/$(sed -n 's/^name *= *"\(.*\)"/\1/p' "$APPMOD/moon.mod")/$PKG/$PKG.exe
fi

sync() {
  mkdir -p $M/src
  cp -p moon.mod $M/
  # exactly src/: a file gone from it goes from the copy too (then the copy's own files, after; Git Bash has no rsync)
  if command -v rsync >/dev/null; then rsync -a --delete src/ $M/src/; else rm -rf $M/src && cp -rp src $M/src; fi
  sed -e 's/"native-stub": *\[[^]]*\]/"native-stub": [ "win_app.c", "win_render.cpp", "win_text.cpp", "win_image.cpp", "win_listen.c", "win_browser_login.c", "win_views.cpp" ]/' \
      -e 's/-fobjc-arc *//' src/host/moon.pkg > $M/src/host/moon.pkg
  # every app (demo, photos…) links no Apple frameworks
  for p in src/*/moon.pkg; do
    grep -q '"is-main"' $p && sed -e '/"cc-link-flags"/d' $p > $M/$p
  done
  # WebView2's SDK (win_views.cpp): its header beside the host's sources, its static loader where the linker looks
  cp -p "$WV2/build/native/include/WebView2.h" $M/src/host/
  [ ! -f src/photos/pictures/windows.mbt ] || cp -p src/photos/pictures/windows.mbt $M/src/photos/pictures_native.mbt
  if ! grep -q win_app.c $M/src/host/moon.pkg || grep -q -e -framework -e '\.m"' $M/src/*/moon.pkg; then
    echo "win.sh: src/host/moon.pkg or an app's moon.pkg no longer has the expected shape" >&2
    exit 1
  fi
  [ -z "$APPMOD" ] || sync_app
}

# the other module's copy: its sources, its workspace naming the copy of mbui above, its apps linking nothing of Apple's
sync_app() {
  mkdir -p $AM
  cp -p "$APPMOD/moon.mod" $AM/
  rm -rf $AM/src && cp -rp "$APPMOD/src" $AM/src
  printf 'members = [\n  ".",\n  "../mod",\n]\n' > $AM/moon.work
  # (its packages with Apple's own native stubs, a core host's: their Windows one, win_engine.c, instead, else left out)
  for p in $(grep -l '\.m"' $AM/src/*/moon.pkg 2>/dev/null); do
    if [ -f "$(dirname $p)/win_engine.c" ]; then
      sed -i -e 's/"native-stub": *\[[^]]*\.m"[^]]*\]/"native-stub": [ "win_engine.c" ]/' -e 's/-fobjc-arc *//' $p
    else
      rm -rf "$(dirname $p)"
    fi
  done
  for p in $AM/src/*/moon.pkg; do
    grep -q '"is-main"' $p && sed -i -e '/"cc-link-flags"/d' $p
  done
  true
}

# WebView2's SDK, from NuGet (the header and the loader linked in statically; the browser is the system's own runtime)
WV2_VERSION=1.0.4258.31
WV2=out/webview2/$WV2_VERSION
webview2_sdk() {
  [ -f $WV2/build/native/include/WebView2.h ] && return
  mkdir -p out/webview2
  curl -sSfL --retry 3 -o $WV2.nupkg "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$WV2_VERSION"
  PY=$(command -v python || command -v python3)
  "$PY" -m zipfile -e "$WV2.nupkg" $WV2
  rm -f $WV2.nupkg
}

shot_dir() {
  rm -rf "$1"; mkdir -p "$1"
  cygpath -w "$PWD/$1"
}

case "${1:-build}" in
  build)
    webview2_sdk
    export LIB="$(cygpath -w "$PWD/$WV2/build/native/x64");$LIB"
    sync
    # moon's build, with the C that moonc generates split and compiled by cl in parallel, moonbit_init at /O1
    # (scripts/mbc.py: a cl.exe first on PATH, every other command passed to the real one; MBC_SPLIT=0 compiles it
    # whole). Windows' python is `python`.
    PY=$(command -v python || command -v python3)
    SHIM=$(cygpath -u "$("$PY" "$D/mbc.py" shim "$(cygpath -w "$PWD/out/mbc/win")" | tr -d '\r')")
    rm -f out/mbc.log
    LOG=$(cygpath -w "$PWD/out/mbc.log")
    code=0
    B=$M; [ -z "$APPMOD" ] || B=$AM
    (cd $B && export PATH="$SHIM:$PATH" MBC_LOG="$LOG" MBC_VERBOSE=1 && time moon build --target native $FLAG src/$PKG) || code=$?
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
