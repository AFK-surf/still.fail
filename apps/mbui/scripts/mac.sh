#!/bin/bash
# The macOS apps: mbui's scripts/mac.sh (build | run | script NAME | shot | bench) on this module's apps (APP=stillfail
# by default; sffix, sfkit, coredemo, photos, books). stillfail and coredemo have the still.fail core in them, in Hermes:
# Hermes's framework, the engine, the Rust shell's .a and the core's bytecode (scripts/core.sh apple) made first when
# missing or stale (a new engine links the app again); `login` runs the core demo
# signing in the way a command-line tool does (MBUI_AUTH_LOGIN): what a station's remote login runs on this machine.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
export APP=${APP:-stillfail}
[ "${1:-}" = login ] && export APP=coredemo
if [ "${MBUI_CORE:-0}" != 0 ]; then export APP=coredemo; fi
if [ $APP = coredemo ] || [ $APP = stillfail ]; then
  if [ "${1:-build}" = build ]; then
    bash "$D/core.sh" apple aarch64-apple-darwin || exit 1
    # (moon does not see the engine's archive: an app linked before it was made has its stub touched, so it is linked
    # again)
    exe=$A/_build/native/${MODE:-release}/build/stillfail/$APP/$APP.exe
    [ ! -f "$exe" ] || [ ! "$A/out/core/aarch64-apple-darwin/libmbui_core.a" -nt "$exe" ] || touch "$A/src/$APP/core_engine.m"
  fi
  export MB_CORE_BUNDLE=${MB_CORE_BUNDLE:-$A/out/core/core.hbc}
fi
if [ "${1:-}" = login ]; then
  cd "$A" && MBUI_AUTH_LOGIN=1 exec ./_build/native/${MODE:-release}/build/coredemo/coredemo.exe
fi
exec bash "$MBUI_DIR/scripts/mac.sh" "$@"
