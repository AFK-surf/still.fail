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
#   scripts/win.sh engine-sync             synchronous host answers across the engine DLL checked
#   scripts/win.sh sealed                  the desktop app's sealed values opened (src/host/win_electron_sealed.h) checked
#   scripts/win.sh setup                   the installer (windows/setup.c) with the app built and put packed after it
#   scripts/win.sh setup-bare              the installer's own program alone (out/setup-bare), which setup packs the app with
# Its identity (as mac-app.sh's Info.plist has the Mac app's), in the program's resources: its icon
# (windows/AppIcon-<mac-icon.swift's hash>.ico: that script draws it on a Mac, `--ico`), its version (0.1.<MBUI_BUILD>,
# else the commits in still.fail's history), its name, and its own environment (RCDATA MBUI_ENV, which mbui's host
# reads as what the process's environment does not say: src/host/win_life.h): MBUI_APP_ID, MBUI_APP_NAME,
# MBUI_SCHEMES, MBUI_OWN, MBUI_BETA. MBUI_VARIANT, which app it is built as (as mac-app.sh's): preview (the default) still.fail
# preview, an app beside still.fail's desktop app (fail.still.mbui, the test channel's, no links of that app's); stable and
# beta still.fail's desktop app itself, to take its place (apps/desktop/package.json, build.sh): its id
# (fail.still.desktop, .beta: its AppUserModelID, its pinned shortcuts'), its name (still.fail, youdid.wtf: its
# userData, %APPDATA%\<name>, whose data, sign-in and sealed keys it takes: src/host/win_core.c), its links (stillfail,
# stillfail-beta), MBUI_OWN; the beta's core a beta's.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
# Every app build, including release variants, picks the same compiler before mbc looks up its objects.
if [ "${1:-build}" = build ]; then . "$D/win-compiler.sh"; fi
export APP=${APP:-stillfail}
if [ "$APP" = stillfail ]; then
  engine=$(cd "$SF_SRC" && node scripts/native.ts path engine win32-x64) || exit 1
  shell=$(cd "$SF_SRC" && node scripts/native.ts path shell win32-x64) || exit 1
  # (the shell's import library too: the app asks the shell itself for a remote screen's frames, src/host/win_core.c)
  export LIB="$(cygpath -w "$engine");$(cygpath -w "$shell");$LIB"
  export CL="/I$(cygpath -w "$A/engine") /I$(cygpath -w "$MBUI_DIR/src/host") ${CL:-}"
fi
core() { HERMESC=$(cygpath -m "$engine/hermesc.exe") bash "$D/core.sh" hermes; }
# variant: what MBUI_VARIANT builds the app as: its id, its name, its program's name where it is put (the desktop app's
# own program's in its place), the folder it is put in (%LOCALAPPDATA%\Programs\<dir>: the desktop app's installer's,
# its package name), and its own environment beyond those
MONOID_ENV='MBUI_OWN=1\nMBUI_UPDATE_FEED=win\nMBUI_CLOUD=https://app.monoid.build\nMBUI_PRODUCT=monoid\nMBUI_STATION_ID=monoid\nMBUI_STATION_NAME=monoid'
variant() {
  case "${MBUI_VARIANT:-preview}" in
    preview) id=fail.still.mbui name="still.fail preview" exe=stillfail dir=stillfail-mbui schemes= extra='MBUI_BETA=1\nMBUI_UPDATE_FEED=win/mbui' ;;
    stable) id=fail.still.desktop name=still.fail exe=still.fail dir=stillfail schemes=stillfail extra='MBUI_OWN=1\nMBUI_UPDATE_FEED=win' ;;
    beta) id=fail.still.desktop.beta name=youdid.wtf exe=youdid.wtf dir=stillfail-beta schemes=stillfail-beta extra='MBUI_OWN=1\nMBUI_BETA=1\nMBUI_UPDATE_FEED=win' ;;
    # monoid's: the same app on monoid's cloud, its station its own (~\.monoid, 「monoid station」: install-windows.ts)
    monoid) id=build.monoid.desktop name=monoid exe=monoid dir=monoid schemes=monoid extra="$MONOID_ENV" ;;
    monoid-beta) id=build.monoid.desktop.beta name=monoid.zone exe=monoid.zone dir=monoid-beta schemes=monoid-beta extra="$MONOID_ENV\nMBUI_BETA=1" ;;
    *) echo "win.sh: MBUI_VARIANT is preview, stable, beta, monoid or monoid-beta, not $MBUI_VARIANT" >&2; return 1 ;;
  esac
}
# res: the app's resources (out/win-res/app.res), for mbui's win.sh to link into it (MBUI_WIN_RES)
res() {
  local n=${MBUI_BUILD:-$(git -C "$SF_SRC" rev-list --count HEAD 2>/dev/null || echo 1)}
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
  # (one name whatever is in it, the app's link flags the same from one build to the next: named by its content, a
  # version's every commit made the app package's moon.pkg another and moon built all of it again, moonc and its C split
  # anew, ~45 s of a Windows preview with nothing of its MoonBit changed, 2026-11-05. moon links the program again only
  # as an input it knows changes, which these resources are not: where they are not what the program was linked with
  # (kept beside it), the program is taken away, and moon links it again alone; mbc's link goes by its inputs' content)
  local res=$r/app.linked.res
  . "$MBUI_DIR/scripts/env.sh"
  # (a build before this one's: none, nothing linked yet)
  if [ -f "$MBUI_DIR/out/win/app/moon.work" ]; then
    local built=$MBUI_DIR/out/win/app/$(cd "$MBUI_DIR/out/win/app" && pkg_build $APP native ${MODE:-release})
    if ! cmp -s "$r/app.res" "$built/app.res"; then
      rm -f "$built/stillfail.exe"
      mkdir -p "$built" && cp "$r/app.res" "$built/app.res"
    fi
  fi
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
# The real engine DLL takes host answers through its C ABI (the host and the engine have separate CRTs).
engine_sync() {
  . "$MBUI_DIR/scripts/env.sh"
  local built=$MBUI_DIR/out/win/app/$(cd "$MBUI_DIR/out/win/app" && pkg_build $APP native ${MODE:-release}) out=$A/out/engine-sync
  mkdir -p "$out/data"
  (cd "$A" && cl.exe -nologo -O2 -W3 -Iengine -Isrc/host core/engine_sync_test_win.c \
    -Fe"$(cygpath -w "$built/engine_sync_test.exe")" -Fo"$(cygpath -w "$out/")" > "$out/build.log") || { cat "$out/build.log"; return 1; }
  "$built/engine_sync_test.exe" "$(cygpath -m "$out/data")"
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
# 2026-10-28). -utf-8: its Chinese words, read in the build machine's code page without it, were garbled in the program
setup_bare() {
  local out=$A/out/setup-bare
  [ "$out/setup-bare.exe" -nt "$A/windows/setup.c" ] && return 0
  mkdir -p "$out"
  local t0=$SECONDS
  (cd "$A" && cl.exe -nologo -O2 -W3 -utf-8 windows/setup.c -Fe"$(cygpath -w "$out/setup-bare.exe.tmp.exe")" -Fo"$(cygpath -w "$out/")" > "$out/build.log") ||
    { cat "$out/build.log"; return 1; }
  mv -f "$out/setup-bare.exe.tmp.exe" "$out/setup-bare.exe"
  echo "win.sh: setup.c compiled in $((SECONDS - t0)) s"
}
# Check the actual programs that will be installed, not just the compiler options: a prebuilt DLL can bring its own
# runtime dependency. Windows 10 includes the UCRT, but not the Visual C++ redistributable.
check_crt() {
  local file deps bad=0
  for file in "$@"; do
    [ -f "$file" ] || { echo "win.sh: no $file to check" >&2; return 1; }
    deps=$(dumpbin.exe -nologo -dependents "$(cygpath -w "$file")") || return 1
    printf '%s\n%s\n' "Dependencies of $(basename "$file"):" "$deps"
    if printf '%s\n' "$deps" | grep -Eiq '(^|[[:space:]])(MSVCP|VCRUNTIME)[0-9_]*\.dll([[:space:]]|$)'; then
      echo "win.sh: $(basename "$file") needs the Visual C++ redistributable" >&2
      bad=1
    fi
  done
  return "$bad"
}
setup() {
  local n=${MBUI_BUILD:-$(git -C "$SF_SRC" rev-list --count HEAD 2>/dev/null || echo 1)} id name exe dir schemes extra
  variant || return 1
  . "$MBUI_DIR/scripts/env.sh"
  local built=$MBUI_DIR/out/win/app/$(cd "$MBUI_DIR/out/win/app" && pkg_build $APP native ${MODE:-release}) out=${MBUI_SETUP_OUT:-$A/out/setup}
  [ -f "$built/stillfail.exe" ] || { echo "win.sh: no app built (win.sh build, put)" >&2; return 1; }
  rm -rf "$out" && mkdir -p "$out/files"
  setup_bare || return 1
  check_crt "$A/out/setup-bare/setup-bare.exe" "$built/stillfail.exe" "$built/stillfail_engine.dll" "$built/stillfail_shell.dll" || return 1
  cp "$A/out/setup-bare/setup-bare.exe" "$out/setup-bare.exe"
  cp "$built/stillfail.exe" "$out/files/$exe.exe"
  cp "$built/stillfail_engine.dll" "$built/stillfail_shell.dll" "$built/core.hbc" "$out/files/"
  printf 'APP_NAME=%s\nAPP_ID=%s\nEXE=%s\nDIR=%s\nSCHEMES=%s\nVERSION=0.1.%s\n' "$name" "$id" "$exe" "$dir" "$schemes" "$n" > "$out/setup.env"
  local to=$out/${MBUI_SETUP_NAME:-stillfail-setup-0.1.$n.exe}
  local w=(); for f in "$out/files/"*; do w+=("$(cygpath -w "$f")"); done
  "$out/setup-bare.exe" --pack "$(cygpath -w "$to")" "$(cygpath -w "$out/setup.env")" "${w[@]}" || return 1
  echo "win.sh: $(basename "$to") $(wc -c < "$to") bytes ($name 0.1.$n)"
}
app_prebuild() {
  if [ "$APP" = stillfail ] && [ "${MBUI_WIN_CORE:-1}" != 0 ]; then core || exit 1; fi
  if [ "$APP" = stillfail ]; then res || exit 1; fi
}
app_postbuild() {
  if [ "$APP" = stillfail ]; then
    if [ "${MBUI_WIN_CORE:-1}" != 0 ]; then put core || exit 1; else put || exit 1; fi
  fi
}
app_cmd() {
  case "$1" in
    core) core ;;
    put) put core ;;
    collate) collate ;;
    engine-sync) engine_sync ;;
    sealed) sealed ;;
    setup) setup ;;
    setup-bare) setup_bare ;;
    *) echo "win.sh: no command $1" >&2; exit 1 ;;
  esac
}
[ -z "${MBUI_IN_WIN_SH:-}" ] || { return 0 2>/dev/null || exit 0; }
export MBUI_IN_WIN_SH=1 MBUI_WIN_HOOK="$D/win.sh"
exec bash "$MBUI_DIR/scripts/win.sh" "$@"
