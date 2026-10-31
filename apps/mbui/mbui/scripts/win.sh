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
# Windows), else is left out. MBUI_WIN_RES=<a .res>: the app's resources (its icon, its version, its own environment:
# still.fail's scripts/win.sh makes them), linked into APP's program.
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
SM=out/win/stage/mod
SA=out/win/stage/app
PY=$(command -v python || command -v python3)
if [ -n "$APPMOD" ]; then
  EXE=$AM/_build/native/$MODE/build/$(sed -n 's/^name *= *"\(.*\)"/\1/p' "$APPMOD/moon.mod")/$PKG/$PKG.exe
fi

# Each build's copies made afresh in out/win/stage, then mirrored into out/win/mod and out/win/app (scripts/mbc
# mirror: a file only written when its content changed), so that moon, which goes by mtimes, builds anew only what
# changed: a build of the same sources (a cache of out/win, as still.fail's CI has) compiles nothing.
sync() {
  rm -rf $SM && mkdir -p $SM/src
  cp -p moon.mod $SM/
  # exactly src/: a file gone from it goes from the copy too (then the copy's own files, after)
  cp -rp src/. $SM/src/
  sed -e 's/"native-stub": *\[[^]]*\]/"native-stub": [ "win_app.c", "win_render.cpp", "win_text.cpp", "win_image.cpp", "win_listen.c", "win_browser_login.c", "win_passwords.c", "win_views.cpp", "win_stream.cpp", "win_notify.cpp", "win_a11y.cpp" ]/' \
      -e 's/-fobjc-arc *//' src/host/moon.pkg > $SM/src/host/moon.pkg
  # every app (demo, photos…) links no Apple frameworks
  for p in src/*/moon.pkg; do
    grep -q '"is-main"' $p && sed -e '/"cc-link-flags"/d' $p > $SM/$p
  done
  # WebView2's SDK (win_views.cpp): its header beside the host's sources, its static loader where the linker looks
  cp -p "$WV2/build/native/include/WebView2.h" $SM/src/host/
  [ ! -f src/photos/pictures/windows.mbt ] || cp -p src/photos/pictures/windows.mbt $SM/src/photos/pictures_native.mbt
  if ! grep -q win_app.c $SM/src/host/moon.pkg || grep -q -e -framework -e '\.m"' $SM/src/*/moon.pkg; then
    echo "win.sh: src/host/moon.pkg or an app's moon.pkg no longer has the expected shape" >&2
    exit 1
  fi
  "$D/mbc" mirror $SM $M
  [ -z "$APPMOD" ] || sync_app
}

# the other module's copy: its sources, its workspace naming the copy of mbui above, its apps linking nothing of Apple's
sync_app() {
  rm -rf $SA && mkdir -p $SA
  cp -p "$APPMOD/moon.mod" $SA/
  cp -rp "$APPMOD/src" $SA/src
  printf 'members = [\n  ".",\n  "../mod",\n]\n' > $SA/moon.work
  # (its packages with Apple's own native stubs, a core host's: their Windows one, win_engine.c, instead, else left out)
  for p in $(grep -l '\.m"' $SA/src/*/moon.pkg 2>/dev/null); do
    if [ -f "$(dirname $p)/win_engine.c" ]; then
      sed -i -e 's/"native-stub": *\[[^]]*\.m"[^]]*\]/"native-stub": [ "win_engine.c" ]/' -e 's/-fobjc-arc *//' $p
    else
      rm -rf "$(dirname $p)"
    fi
  done
  for p in $SA/src/*/moon.pkg; do
    grep -q '"is-main"' $p && sed -i -e '/"cc-link-flags"/d' $p
  done
  [ -z "${MBUI_WIN_RES:-}" ] || win_res $SA/src/$PKG/moon.pkg
  "$D/mbc" mirror $SA $AM
}

# The app's resources (MBUI_WIN_RES) in its link: its cc-link-flags, which moon puts after cl's /link for MSVC, where
# link.exe takes a .res as it takes an object (and mbc's link, finding the file named there, goes by its content)
win_res() {
  local res
  res=$(cygpath -m "$MBUI_WIN_RES")
  case "$res" in *" "*) echo "win.sh: $res: a path with a space, which cc-link-flags cannot take" >&2; exit 1 ;; esac
  grep -q '"native": *{' "$1" || { echo "win.sh: $1 has no native link options to put the resources in" >&2; exit 1; }
  sed -i -e "s#\"native\": *{#\"native\": {\n      \"cc-link-flags\": \"$res\",#" "$1"
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
    # (scripts/mbc: a cl.exe first on PATH, every other command passed to the real one; MBC_SPLIT=0 compiles it
    # whole)
    SHIM=$(cygpath -u "$("$D/mbc" shim "$(cygpath -w "$PWD/out/mbc/win")" | tr -d '\r')")
    # cl's and link's outputs reproducible (-Brepro: no time stamps in them; lib's is mbc shim's), so that the same C
    # makes the same objects and mbc's link, finding its inputs as they were, is not run again (an LTCG link is run
    # without it, by scripts/mbc: /LTCG:INCREMENTAL takes nothing of the last link's otherwise). (-, not /: Git Bash
    # hands a variable's /Brepro to Windows programs as a path, C:/Program Files/Git/Brepro)
    export CL="-Brepro ${CL:-}" LINK="-Brepro ${LINK:-}"
    rm -f out/mbc.log
    LOG=$(cygpath -w "$PWD/out/mbc.log")
    code=0
    B=$M; [ -z "$APPMOD" ] || B=$AM
    # (its warnings a line each, not rendered: moon renders them, ~600-1100 with their sources, after the last task,
    # 5-10 s of the runner's one core with nothing else of the build left, as moon's --trace shows, still.fail's CI,
    # 2026-10-24)
    (cd $B && export PATH="$SHIM:$PATH" MBC_LOG="$LOG" MBC_VERBOSE=1 && time moon build --no-render --target native $FLAG src/$PKG) || code=$?
    cat out/mbc.log 2>/dev/null || echo "win.sh: moon ran no command through scripts/mbc (out/mbc/win)"
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
