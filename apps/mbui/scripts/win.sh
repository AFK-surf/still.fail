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
#   scripts/win.sh collate                 the host's order of names (src/host/win_collate.h) checked
# Its identity (as mac-app.sh's Info.plist has the Mac app's), in the program's resources: its icon
# (windows/AppIcon-<mac-icon.swift's hash>.ico: that script draws it on a Mac, `--ico`), its version (0.1.<MBUI_BUILD>,
# else the commits in still.fail's history), its name, and its own environment (RCDATA MBUI_ENV, which mbui's host
# reads as what the process's environment does not say: src/host/win_life.h): MBUI_APP_ID, MBUI_APP_NAME, MBUI_BETA.
# Built as still.fail mbui (fail.still.mbui, an app beside still.fail's desktop app, on the test channel: it takes no
# links, MBUI_SCHEMES, of that app's).
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
# res: the app's resources (out/win-res/app.res), for mbui's win.sh to link into it (MBUI_WIN_RES)
res() {
  local n=${MBUI_BUILD:-$(git -C "$EMBER" rev-list --count HEAD 2>/dev/null || echo 1)}
  local icon=$A/windows/AppIcon-$(sha256sum "$D/mac-icon.swift" | cut -c1-12).ico
  [ -f "$icon" ] || { echo "win.sh: no $icon (scripts/mac-icon.swift changed: swift scripts/mac-icon.swift --ico $icon, on a Mac)" >&2; return 1; }
  local id=fail.still.mbui name="still.fail mbui" r=$A/out/win-res
  rm -rf "$r" && mkdir -p "$r"
  cp "$icon" "$r/app.ico"
  printf 'MBUI_APP_ID=%s\nMBUI_APP_NAME=%s\nMBUI_BETA=1\n' "$id" "$name" > "$r/app.env"
  cat > "$r/app.rc" <<RC
1 ICON "app.ico"
MBUI_ENV RCDATA "app.env"
1 VERSIONINFO
 FILEVERSION 0,1,$n,0
 PRODUCTVERSION 0,1,$n,0
 FILEFLAGSMASK 0x3F
 FILEFLAGS 0
 FILEOS 0x40004
 FILETYPE 0x1
 FILESUBTYPE 0
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040904B0"
    BEGIN
      VALUE "CompanyName", "AFK AI, Inc."
      VALUE "FileDescription", "$name"
      VALUE "FileVersion", "0.1.$n"
      VALUE "InternalName", "stillfail"
      VALUE "OriginalFilename", "stillfail.exe"
      VALUE "ProductName", "$name"
      VALUE "ProductVersion", "0.1.$n"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x409, 1200
  END
END
RC
  # (rc's options with -, not /: Git Bash hands /fo to Windows programs as a path)
  (cd "$r" && rc.exe -nologo -fo app.res app.rc) || return 1
  export MBUI_WIN_RES=$r/app.res
  echo "win.sh: $name 0.1.$n ($id), its resources $(wc -c < "$r/app.res") bytes"
}
# put [core]: the engine and the shell beside the app's .exe, the core's bytecode too when asked
put() {
  . "$MBUI_DIR/scripts/env.sh"
  # (mbui's win.sh builds this module in its copy, out/win/app beside mbui's own)
  dir=$MBUI_DIR/out/win/app/$(cd "$MBUI_DIR/out/win/app" && pkg_build $APP native ${MODE:-release})
  cp "$engine/stillfail_engine.dll" "$shell/stillfail_shell.dll" "$dir/" || return 1
  [ "${1:-}" != core ] || cp "$A/out/core/core.hbc" "$dir/" || return 1
  ls -la "$dir"
}
# collate: the order of names the core asks of the host (src/host/win_collate.h), checked by core/collate_test_win.c
collate() {
  local out=$A/out/collate
  mkdir -p "$out"
  (cd "$A" && cl.exe -nologo -O2 -W3 -Isrc/host core/collate_test_win.c -Fe"$(cygpath -w "$out/collate_test_win.exe")" \
    -Fo"$(cygpath -w "$out/")" > "$out/build.log") || { cat "$out/build.log"; return 1; }
  "$out/collate_test_win.exe"
}
case "${1:-build}" in
  core) core; exit $? ;;
  put) put core; exit $? ;;
  collate) collate; exit $? ;;
esac
if [ "$APP" = stillfail ] && [ "${1:-build}" = build ] && [ "${MBUI_WIN_CORE:-1}" != 0 ]; then
  core || exit 1
fi
if [ "$APP" = stillfail ] && [ "${1:-build}" = build ]; then
  res || exit 1
fi
bash "$MBUI_DIR/scripts/win.sh" "$@" || exit $?
if [ "$APP" = stillfail ] && [ "${1:-build}" = build ]; then
  if [ "${MBUI_WIN_CORE:-1}" != 0 ]; then put core; else put; fi
fi
