#!/bin/bash
# The macOS apps: mbui's scripts/mac.sh (build | run | script NAME | shot | bench) on this module's apps (APP=stillfail
# by default; sffix, sfkit, coredemo, photos, books). stillfail and coredemo have the still.fail core in them: the Rust
# shell's .a and the core's script (scripts/core.sh shell, bundle) made first when missing; `login` runs the core demo
# signing in the way a command-line tool does (MBUI_AUTH_LOGIN): what a station's remote login runs on this machine.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
export APP=${APP:-stillfail}
[ "${1:-}" = login ] && export APP=coredemo
if [ "${MBUI_CORE:-0}" != 0 ]; then export APP=coredemo; fi
if [ $APP = coredemo ] || [ $APP = stillfail ]; then
  [ -f "$A/out/core/aarch64-apple-darwin/libstillfail_shell.a" ] || bash "$D/core.sh" shell || exit 1
  [ -f "$A/out/core/core.js" ] || bash "$D/core.sh" bundle || exit 1
  export MB_CORE_BUNDLE=${MB_CORE_BUNDLE:-$A/out/core/core.js}
fi
if [ "${1:-}" = login ]; then
  cd "$A" && MBUI_AUTH_LOGIN=1 exec ./_build/native/${MODE:-release}/build/coredemo/coredemo.exe
fi
exec bash "$MBUI_DIR/scripts/mac.sh" "$@"
