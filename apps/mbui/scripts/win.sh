#!/bin/bash
# The Windows apps: mbui's scripts/win.sh (build | run | script NAME | shot) on this module's apps (APP=stillfail by
# default; sffix, sfkit), in Git Bash on Windows with MoonBit and MSVC (a Developer Command Prompt's environment).
# stillfail has the still.fail core in it (src/stillfail/win_engine.c → src/host/win_core.c): the engine and the shell
# prebuilt for Windows (this checkout's scripts/native.ts parts `engine` and `shell`, win32-x64: from the release
# native-artifacts, or built here, as only Windows can), the engine's C API (engine/engine.h) and import library found
# through cl's and link's own variables (CL, LIB), and the core as Hermes bytecode (scripts/core.sh hermes, with the
# engine's own hermesc). After a build all three are put beside the app's .exe, which finds them there.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
export APP=${APP:-stillfail}
if [ "$APP" = stillfail ]; then
  engine=$(cd "$EMBER" && node scripts/native.ts path engine win32-x64) || exit 1
  shell=$(cd "$EMBER" && node scripts/native.ts path shell win32-x64) || exit 1
  export LIB="$(cygpath -w "$engine");$LIB"
  export CL="/I$(cygpath -w "$A/engine") /I$(cygpath -w "$MBUI_DIR/src/host") ${CL:-}"
  if [ "${1:-build}" = build ]; then
    HERMESC=$(cygpath -m "$engine/hermesc.exe") bash "$D/core.sh" hermes || exit 1
  fi
fi
bash "$MBUI_DIR/scripts/win.sh" "$@" || exit $?
if [ "$APP" = stillfail ] && [ "${1:-build}" = build ]; then
  . "$MBUI_DIR/scripts/env.sh"
  # (mbui's win.sh builds this module in its copy, out/win/app beside mbui's own)
  dir=$MBUI_DIR/out/win/app/$(cd "$MBUI_DIR/out/win/app" && pkg_build $APP native ${MODE:-release})
  cp "$engine/stillfail_engine.dll" "$shell/stillfail_shell.dll" "$A/out/core/core.hbc" "$dir/"
  ls -la "$dir"
fi
