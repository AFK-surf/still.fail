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
#   scripts/win.sh sealed                  the desktop app's sealed values opened (src/host/win_electron_sealed.h) checked
#   scripts/win.sh setup                   the installer (windows/setup.c) with the app built and put packed after it
#   scripts/win.sh setup-bare              the installer's own program alone (out/setup-bare), which setup packs the app with
# Its identity (as mac-app.sh's Info.plist has the Mac app's), in the program's resources: its icon
# (windows/AppIcon-<mac-icon.swift's hash>.ico: that script draws it on a Mac, `--ico`), its version (0.1.<MBUI_BUILD>,
# else the commits in still.fail's history), its name, and its own environment (RCDATA MBUI_ENV, which mbui's host
# reads as what the process's environment does not say: src/host/win_life.h): MBUI_APP_ID, MBUI_APP_NAME,
# MBUI_SCHEMES, MBUI_OWN, MBUI_BETA. MBUI_VARIANT, which app it is built as (as mac-app.sh's): mbui (the default) still.fail
# mbui, an app beside still.fail's desktop app (fail.still.mbui, the test channel's, no links of that app's); stable and
# beta still.fail's desktop app itself, to take its place (apps/desktop/package.json, build.sh): its id
# (fail.still.desktop, .beta: its AppUserModelID, its pinned shortcuts'), its name (still.fail, youdid.wtf: its
# userData, %APPDATA%\<name>, whose data, sign-in and sealed keys it takes: src/host/win_core.c), its links (stillfail
# and ember, stillfail-beta), MBUI_OWN; the beta's core a beta's.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
# Every app build, including release variants, picks the same compiler before mbc looks up its objects.
if [ "${1:-build}" = build ]; then . "$D/win-compiler.sh"; fi
export APP=${APP:-stillfail}
if [ "$APP" = stillfail ]; then
  engine=$(cd "$EMBER" && node scripts/native.ts path engine win32-x64) || exit 1
  shell=$(cd "$EMBER" && node scripts/native.ts path shell win32-x64) || exit 1
  # (the shell's import library too: the app asks the shell itself for a remote screen's frames, src/host/win_core.c)
  export LIB="$(cygpath -w "$engine");$(cygpath -w "$shell");$LIB"
  export CL="/I$(cygpath -w "$A/engine") /I$(cygpath -w "$MBUI_DIR/src/host") ${CL:-}"
fi
core() { HERMESC=$(cygpath -m "$engine/hermesc.exe") bash "$D/core.sh" hermes; }
# variant: what MBUI_VARIANT builds the app as: its id, its name, its program's name where it is put (the desktop app's
# own program's in its place), the folder it is put in (%LOCALAPPDATA%\Programs\<dir>: the desktop app's installer's,
# its package name), and its own environment beyond those
variant() {
  case "${MBUI_VARIANT:-mbui}" in
    mbui) id=fail.still.mbui name="still.fail mbui" exe=stillfail dir=stillfail-mbui schemes= extra='MBUI_BETA=1\nMBUI_UPDATE_FEED=win/mbui' ;;
    stable) id=fail.still.desktop name=still.fail exe=still.fail dir=stillfail schemes=stillfail,ember extra='MBUI_OWN=1\nMBUI_UPDATE_FEED=win' ;;
    beta) id=fail.still.desktop.beta name=youdid.wtf exe=youdid.wtf dir=stillfail-beta schemes=stillfail-beta extra='MBUI_OWN=1\nMBUI_BETA=1\nMBUI_UPDATE_FEED=win' ;;
    *) echo "win.sh: MBUI_VARIANT is mbui, stable or beta, not $MBUI_VARIANT" >&2; return 1 ;;
  esac
}
# res: the app's resources (out/win-res/app.res), for mbui's win.sh to link into it (MBUI_WIN_RES)
res() {
  local n=${MBUI_BUILD:-$(git -C "$EMBER" rev-list --count HEAD 2>/dev/null || echo 1)}
  local icon=$A/windows/AppIcon-$(sha256sum "$D/mac-icon.swift" | cut -c1-12).ico
  [ -f "$icon" ] || { echo "win.sh: no $icon (scripts/mac-icon.swift changed: swift scripts/mac-icon.swift --ico $icon, on a Mac)" >&2; return 1; }
  local id name exe dir schemes extra r=$A/out/win-res
  variant || return 1
  [ -z "$schemes" ] || extra="MBUI_SCHEMES=$schemes\n$extra"
  rm -rf "$r" && mkdir -p "$r"
  cp "$icon" "$r/app.ico"
  printf "MBUI_APP_ID=%s\nMBUI_APP_NAME=%s\n$extra\n" "$id" "$name" > "$r/app.env"
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
      VALUE "OriginalFilename", "$exe.exe"
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
  # (named by what is in it: moon links the program again only for a link of other inputs, the link's flags among
  # them, and so for resources that changed, another variant's or version's, as their name does; the same name, an
  # app built before linked none of them and kept the resources it had)
  local res=$r/app-$(sha256sum "$r/app.res" | cut -c1-16).res
  cp "$r/app.res" "$res"
  export MBUI_WIN_RES=$res
  echo "win.sh: $name 0.1.$n ($id), its resources $(wc -c < "$res") bytes ($(basename "$res"))"
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
# sealed: the desktop app's sealed values opened in its place (src/host/win_electron_sealed.h), checked by
# core/sealed_test_win.c
sealed() {
  local out=$A/out/sealed
  mkdir -p "$out"
  (cd "$A" && cl.exe -nologo -O2 -W3 -Isrc/host core/sealed_test_win.c -Fe"$(cygpath -w "$out/sealed_test_win.exe")" \
    -Fo"$(cygpath -w "$out/")" > "$out/build.log") || { cat "$out/build.log"; return 1; }
  "$out/sealed_test_win.exe"
}
# setup: the installer (windows/setup.c) with the app as built and put (put: the program, its engine and shell, core.hbc)
# packed after it, as MBUI_VARIANT has it: <MBUI_SETUP_OUT, else out/setup>/<name> (MBUI_SETUP_NAME, else
# stillfail-setup-0.1.<n>.exe)
# the installer's own program (windows/setup.c), bare: made once for its source, apart from the app (CI makes it while
# the app compiles: made in the installer's step, beside the e2e flow's app, it was 4 s alone and 15-56 s there,
# 2026-10-28)
setup_bare() {
  local out=$A/out/setup-bare
  [ "$out/setup-bare.exe" -nt "$A/windows/setup.c" ] && return 0
  mkdir -p "$out"
  local t0=$SECONDS
  (cd "$A" && cl.exe -nologo -O2 -W3 windows/setup.c -Fe"$(cygpath -w "$out/setup-bare.exe.tmp.exe")" -Fo"$(cygpath -w "$out/")" > "$out/build.log") ||
    { cat "$out/build.log"; return 1; }
  mv -f "$out/setup-bare.exe.tmp.exe" "$out/setup-bare.exe"
  echo "win.sh: setup.c compiled in $((SECONDS - t0)) s"
}
setup() {
  local n=${MBUI_BUILD:-$(git -C "$EMBER" rev-list --count HEAD 2>/dev/null || echo 1)} id name exe dir schemes extra
  variant || return 1
  . "$MBUI_DIR/scripts/env.sh"
  local built=$MBUI_DIR/out/win/app/$(cd "$MBUI_DIR/out/win/app" && pkg_build $APP native ${MODE:-release}) out=${MBUI_SETUP_OUT:-$A/out/setup}
  [ -f "$built/stillfail.exe" ] || { echo "win.sh: no app built (win.sh build, put)" >&2; return 1; }
  rm -rf "$out" && mkdir -p "$out/files"
  setup_bare || return 1
  cp "$A/out/setup-bare/setup-bare.exe" "$out/setup-bare.exe"
  cp "$built/stillfail.exe" "$out/files/$exe.exe"
  cp "$built/stillfail_engine.dll" "$built/stillfail_shell.dll" "$built/core.hbc" "$out/files/"
  printf 'APP_NAME=%s\nAPP_ID=%s\nEXE=%s\nDIR=%s\nSCHEMES=%s\nVERSION=0.1.%s\n' "$name" "$id" "$exe" "$dir" "$schemes" "$n" > "$out/setup.env"
  local to=$out/${MBUI_SETUP_NAME:-stillfail-setup-0.1.$n.exe}
  local w=(); for f in "$out/files/"*; do w+=("$(cygpath -w "$f")"); done
  "$out/setup-bare.exe" --pack "$(cygpath -w "$to")" "$(cygpath -w "$out/setup.env")" "${w[@]}" || return 1
  echo "win.sh: $(basename "$to") $(wc -c < "$to") bytes ($name 0.1.$n)"
}
case "${1:-build}" in
  core) core; exit $? ;;
  put) put core; exit $? ;;
  collate) collate; exit $? ;;
  sealed) sealed; exit $? ;;
  setup) setup; exit $? ;;
  setup-bare) setup_bare; exit $? ;;
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
