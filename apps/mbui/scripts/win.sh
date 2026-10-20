#!/bin/bash
# The Windows apps: mbui's scripts/win.sh (build | run | script NAME | shot) on this module's apps (APP=stillfail by
# default; sffix, sfkit), in Git Bash on Windows with MoonBit and MSVC (a Developer Command Prompt's environment).
# stillfail has the still.fail core in it (src/stillfail/win_engine.c → src/host/win_core.c): the engine and the shell
# prebuilt for Windows (this checkout's scripts/native.ts parts `engine` and `shell`, win32-x64: from the release
# native-artifacts, or built here, as only Windows can), the engine's C API (engine/engine.h) and import library found
# through cl's and link's own variables (CL, LIB), and the core as Hermes bytecode (scripts/core.sh hermes, with the
# engine's own hermesc). After a build all three are put beside the app's .exe, which finds them there.
# The build in parts, for CI to make the core while cl compiles the app (it needs no node_modules; the core does):
#   MBUI_WIN_CORE=0 scripts/win.sh build   the app alone, the engine and the shell put beside it
#   scripts/win.sh core                    the core's bytecode (out/core/core.hbc)
#   scripts/win.sh put                     the core's bytecode, the engine and the shell put beside the app
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
export APP=${APP:-stillfail}
if [ "$APP" = stillfail ]; then
  engine=$(cd "$EMBER" && node scripts/native.ts path engine win32-x64) || exit 1
  shell=$(cd "$EMBER" && node scripts/native.ts path shell win32-x64) || exit 1
  export LIB="$(cygpath -w "$engine");$LIB"
  export CL="/I$(cygpath -w "$A/engine") /I$(cygpath -w "$MBUI_DIR/src/host") ${CL:-}"
fi
core() { HERMESC=$(cygpath -m "$engine/hermesc.exe") bash "$D/core.sh" hermes; }
# put [core]: the engine and the shell beside the app's .exe, the core's bytecode too when asked
put() {
  . "$MBUI_DIR/scripts/env.sh"
  # (mbui's win.sh builds this module in its copy, out/win/app beside mbui's own)
  dir=$MBUI_DIR/out/win/app/$(cd "$MBUI_DIR/out/win/app" && pkg_build $APP native ${MODE:-release})
  cp "$engine/stillfail_engine.dll" "$shell/stillfail_shell.dll" "$dir/" || return 1
  [ "${1:-}" != core ] || cp "$A/out/core/core.hbc" "$dir/" || return 1
  ls -la "$dir"
}
case "${1:-build}" in
  core) core; exit $? ;;
  put) put core; exit $? ;;
esac
if [ "$APP" = stillfail ] && [ "${1:-build}" = build ] && [ "${MBUI_WIN_CORE:-1}" != 0 ]; then
  core || exit 1
fi
bash "$MBUI_DIR/scripts/win.sh" "$@" || exit $?
if [ "$APP" = stillfail ] && [ "${1:-build}" = build ]; then
  if [ "${MBUI_WIN_CORE:-1}" != 0 ]; then put core; else put; fi
fi
