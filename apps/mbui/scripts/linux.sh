#!/bin/bash
# The Linux apps: mbui's scripts/linux.sh (build | run | script NAME | shot) on this module's apps (APP=stillfail by
# default; sffix, sfkit), on Linux with MoonBit, clang and GTK 4's development files (mbui's linux.sh says which).
# stillfail has the still.fail core in it (src/stillfail/linux_engine.c → src/host/linux_core.c): the engine and the
# shell prebuilt for Linux (this checkout's scripts/native.ts parts `engine` and `shell`, linux-x64 or linux-arm64, this
# machine's: from the release native-artifacts, or built here), linked by name and found beside the app as it loads
# ($ORIGIN), the engine's C API (engine/engine.h) on the include path, the desktop's Secret Service through libsecret;
# and the core as Hermes bytecode (scripts/core.sh hermes, with the engine's own hermesc). After a build all three are
# put beside the app's executable.
#   MBUI_LINUX_CORE=0 scripts/linux.sh build   the app alone, the engine and the shell put beside it
#   scripts/linux.sh core                      the core's bytecode (out/core/core.hbc)
#   scripts/linux.sh put                       the core's bytecode, the engine and the shell put beside the app
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
export APP=${APP:-stillfail}
if [ -n "${MBUI_IN_LINUX_SH:-}" ]; then
  if [ "$APP" = stillfail ]; then
    t=linux-$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')
    engine=$(cd "$SF_SRC" && node scripts/native.ts path engine $t) || exit 1
    shell=$(cd "$SF_SRC" && node scripts/native.ts path shell $t) || exit 1
    export MBUI_LINUX_CFLAGS="-I$A/engine -I$MBUI_DIR/src/host $(pkg-config --cflags libsecret-1)"
    export MBUI_LINUX_LDFLAGS="-L$engine -L$shell -lstillfail_engine -lstillfail_shell $(pkg-config --libs libsecret-1) -Wl,-rpath,\$ORIGIN"
  fi
  core() { HERMESC="$engine/hermesc" bash "$D/core.sh" hermes; }
  # put [core]: the engine and the shell beside the app's executable, the core's bytecode too when asked
  put() {
    . "$MBUI_DIR/scripts/env.sh"
    # (mbui's linux.sh builds this module in its copy, out/linux/app beside mbui's own)
    dir=$MBUI_DIR/out/linux/app/$(cd "$MBUI_DIR/out/linux/app" && pkg_build $APP native ${MODE:-release})
    # (the engine's libraries: its own, and ICU's it carries)
    cp "$engine"/lib*.so* "$shell/libstillfail_shell.so" "$dir/" || return 1
    [ "${1:-}" != core ] || cp "$A/out/core/core.hbc" "$dir/" || return 1
    ls -la "$dir"
  }
  app_prebuild() {
    if [ "$APP" = stillfail ] && [ "${MBUI_LINUX_CORE:-1}" != 0 ]; then core || exit 1; fi
  }
  app_postbuild() {
    if [ "$APP" = stillfail ]; then
      if [ "${MBUI_LINUX_CORE:-1}" != 0 ]; then put core || exit 1; else put || exit 1; fi
    fi
  }
  app_cmd() {
    case "$1" in
      core) core ;;
      put) put core ;;
      *) echo "linux.sh: no command $1" >&2; exit 1 ;;
    esac
  }
  return 0 2>/dev/null || exit 0
fi
export MBUI_IN_LINUX_SH=1 MBUI_LINUX_HOOK="$D/linux.sh"
exec bash "$MBUI_DIR/scripts/linux.sh" "$@"
