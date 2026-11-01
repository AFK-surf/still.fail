#!/bin/bash
# The macOS apps: mbui's scripts/mac.sh (build | run | script NAME | shot | bench) on this module's apps (APP=stillfail
# by default; sffix, sfkit, coredemo, photos, books). stillfail and coredemo have the still.fail core in them, in Hermes:
# Hermes's framework, the engine and the Rust shell's .a (scripts/core.sh apple-native) made first when missing or
# stale (a new engine links the app again), the core's bytecode beside the app's compile (only its run and its bundle
# take it: a core changed was ~26 s before the compile on CI's Mac, 2026-10-24); `login` runs the core demo
# signing in the way a command-line tool does (MBUI_AUTH_LOGIN): what a station's remote login runs on this machine.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
export APP=${APP:-stillfail}
[ "${1:-}" = login ] && export APP=coredemo
if [ "${MBUI_CORE:-0}" != 0 ]; then export APP=coredemo; fi
if [ $APP = coredemo ] || [ $APP = stillfail ]; then
  if [ "${1:-build}" = build ]; then
    # (each part's time said, mac-app.sh shows it: a release's Mac job was 185-238 s, the app's part 114-166 s of it,
    # its compile 11 s, the rest not told apart, 2026-11-01)
    t0=$SECONDS
    bash "$D/core.sh" apple-native aarch64-apple-darwin || exit 1
    echo "mac.sh: the core's native parts in $((SECONDS - t0)) s"
    # (moon does not see the engine's archive: an app linked before it was made has its stub touched, so it is linked
    # again)
    exe=$A/_build/native/${MODE:-release}/build/stillfail/$APP/$APP.exe
    [ ! -f "$exe" ] || [ ! "$A/out/core/aarch64-apple-darwin/libmbui_core.a" -nt "$exe" ] || touch "$A/src/$APP/core_engine.m"
    bash "$D/core.sh" hermes apple > "$A/out/core/hermes.log" 2>&1 &
    hbc=$!
  fi
  export MB_CORE_BUNDLE=${MB_CORE_BUNDLE:-$A/out/core/core.hbc}
fi
if [ "${1:-}" = login ]; then
  cd "$A" && MBUI_AUTH_LOGIN=1 exec ./_build/native/${MODE:-release}/build/coredemo/coredemo.exe
fi
[ -n "${hbc:-}" ] || exec bash "$MBUI_DIR/scripts/mac.sh" "$@"
t0=$SECONDS
bash "$MBUI_DIR/scripts/mac.sh" "$@"
code=$?
echo "mac.sh: the app built in $((SECONDS - t0)) s"
t0=$SECONDS
wait $hbc || { cat "$A/out/core/hermes.log"; echo "mac.sh: the core's bytecode was not made (scripts/core.sh hermes apple)" >&2; exit 1; }
cat "$A/out/core/hermes.log"
echo "mac.sh: the core's bytecode waited for $((SECONDS - t0)) s more"
exit $code
