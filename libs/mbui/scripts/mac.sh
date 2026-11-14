#!/bin/bash
# Build the macOS app and run it. MODE=release|debug, APP=demo|textdiff|bench (only that app is built; an app of a module
# outside mbui: MBUI_APP_MOD), then:
#   scripts/mac.sh build | bundle | run [env...] | script ime | bench | shot
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
# MBUI_APP_MOD: an app of a module outside this repository (its moon.work naming mbui; scripts/android.sh says more)
ROOT=$(cd "$D/.." && pwd)
cd "${MBUI_APP_MOD:-$ROOT}"
MODE=${MODE:-release}
FLAG=""; [ "$MODE" = release ] && FLAG=--release
PKG=${APP:-demo}
EXE=$(pkg_build $PKG native $MODE)/$PKG.exe
[ -z "${MBUI_MAC_HOOK:-}" ] || . "$MBUI_MAC_HOOK"
# the photos app shows made-up pictures from out/pictures
[ $PKG = photos ] && [ "${1:-build}" != build ] && [ "${1:-build}" != bundle ] && gallery_pictures
case "${1:-build}" in
  build)
    if type app_prebuild >/dev/null 2>&1; then app_prebuild; fi
    # moon's build, with the C that moonc generates split and compiled in parallel (scripts/mbc: a `cc` first on
    # PATH that moon uses for every C step, all but that one passed through; MBC_SPLIT=0 compiles it whole)
    # (moon's own time and how many tasks it ran said after it, beside mbc's: chk keeps only the errors, and a release's
    # app took 35-75 s with no unit compiled, the rest not told apart, 2026-11-01)
    # (and the packages it compiled again, by their .core made: a release's 51 tasks where one page had changed, main
    # 85827dca, 2026-11-02, the rest not told apart)
    mkdir -p out && rm -f out/mbc.log && touch out/moon.start
    t0=$SECONDS
    PATH="$("$D/mbc" shim "$PWD/out/mbc/bin"):$PATH" MBC_LOG=$PWD/out/mbc.log \
      moon build --target native $FLAG src/$PKG 2>&1 | tee out/moon.log | "$D/chk" errs
    echo "mac.sh: moon's build in $((SECONDS - t0)) s: $(grep -E '^Finished' out/moon.log | tail -1)"
    echo "mac.sh: compiled again: $(find _build/native/$MODE/build -name '*.core' -newer out/moon.start 2>/dev/null |
      sed -E 's#.*/build/##; s#/[^/]+[.]core$##' | sort | tr '\n' ' ')"
    cat out/mbc.log 2>/dev/null || true
    if type app_postbuild >/dev/null 2>&1; then app_postbuild; fi
    ls -la $EXE ;;
  bundle)
    if [ "${MBUI_SKIP_BUILD:-0}" != 1 ] || [ ! -f "$EXE" ]; then bash "$D/mac.sh" build; fi
    OUT=out/mac
    NAME=${MBUI_MAC_NAME:-$PKG}
    ID=${MBUI_APP_ID:-dev.mbui.$PKG}
    N=${MBUI_BUILD:-1}
    EXE_NAME=${MBUI_MAC_EXE:-$NAME}
    APPDIR="$OUT/$NAME.app"
    ZIP=${MBUI_MAC_ZIP:-$OUT/$NAME-mac.zip}
    rm -rf "$APPDIR" "$ZIP"
    mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"
    cp "$EXE" "$APPDIR/Contents/MacOS/$EXE_NAME"
    strip -S -x "$APPDIR/Contents/MacOS/$EXE_NAME"
    PLIST="$APPDIR/Contents/Info.plist"
    plutil -create xml1 "$PLIST"
    for kv in "CFBundleIdentifier $ID" "CFBundleName $NAME" "CFBundleDisplayName $NAME" "CFBundleExecutable $EXE_NAME" \
      "CFBundlePackageType APPL" "CFBundleInfoDictionaryVersion 6.0" "CFBundleShortVersionString 0.1.$N" \
      "CFBundleVersion $N" "LSMinimumSystemVersion ${MACOSX_DEPLOYMENT_TARGET:-13.0}" "NSPrincipalClass NSApplication"; do
      plutil -insert "${kv%% *}" -string "${kv#* }" "$PLIST"
    done
    plutil -insert NSHighResolutionCapable -bool YES "$PLIST"
    plutil -insert NSSupportsAutomaticGraphicsSwitching -bool YES "$PLIST"
    if type app_bundle >/dev/null 2>&1; then app_bundle "$APPDIR"; fi
    codesign --force --sign "${MAC_SIGN_IDENTITY:--}" --timestamp=none "$APPDIR"
    (cd "$OUT" && ditto -c -k --sequesterRsrc --keepParent "$NAME.app" "$(basename "$ZIP")")
    ls -la "$ZIP" ;;
  run)
    on_screen ./$EXE ;;
  script)
    mkdir -p out/$2
    MBUI_SCRIPT=$2 MBUI_SHOT_DIR=$PWD/out/$2 on_screen ./$EXE ;;
  shot)
    mkdir -p out/shot
    MBUI_SCRIPT=shot MBUI_SHOT_DIR=$PWD/out/shot on_screen ./$EXE ;;
  bench)
    MBUI_BENCH=1 on_screen ./$EXE ;;
  *)
    if type app_cmd >/dev/null 2>&1; then app_cmd "$@"; else echo "mac.sh: no command $1" >&2; exit 1; fi ;;
esac
