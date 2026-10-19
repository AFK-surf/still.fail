#!/bin/bash
# still.fail mbui on macOS as an app: out/mac/still.fail mbui.app (fail.still.mbui; arm64, as still.fail's desktop app
# ships), its zip beside it. The app is APP=stillfail's release build (scripts/mac.sh) with what it carries: the core's
# script (Resources/core.js, which the core host finds in the app: src/host/apple_core.m), its icon
# (scripts/mac-icon.swift), an Info.plist of its own. Signed with MAC_SIGN_IDENTITY (CI: still.fail's, imported by
# scripts/mac-sign.py), else ad hoc; checked with codesign's strict verify.
#   apps/mbui/scripts/mac-app.sh            build and bundle it, then sign it (below)
#   apps/mbui/scripts/mac-app.sh build      build and bundle it only (signed ad hoc)
#   apps/mbui/scripts/mac-app.sh sign       sign it (MAC_SIGN_IDENTITY, else ad hoc), check it, zip it:
#                                           out/mac/stillfail-mbui-<n>-arm64-mac.zip (CI: under scripts/mac-sign.py,
#                                           which holds the signing lock only for this)
# The oldest macOS it runs on: still.fail's desktop app's (Electron's: 12.0), MACOSX_DEPLOYMENT_TARGET for clang and
# cargo alike, and its Info.plist's LSMinimumSystemVersion; an object built for a newer one fails the build.
# MBUI_BUILD: the build's number (default git rev-list --count HEAD of still.fail); MBUI_CORE_FRESH=1 makes the core's
# shell and script again (cargo decides what is out of date), else only when missing.
set -eo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
now() { python3 -c 'import time;print(time.time())'; }
secs() { python3 -c "print(f'{$(now)-$1:.1f}')"; }
N=${MBUI_BUILD:-$(git -C "$EMBER" rev-list --count HEAD 2>/dev/null || echo 1)}
NAME="still.fail mbui"
OUT=$A/out/mac
APPDIR="$OUT/$NAME.app"
ZIP=$OUT/stillfail-mbui-$N-arm64-mac.zip
EXE=stillfail-mbui
mkdir -p "$OUT"
t0=$(now)
export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-12.0}
# what was built for another one goes (moon's and mbc's objects, the shell's .a: their keys do not hold it), and the
# Rust shell builds in a target of its own for it
if [ "$(cat _build/.macos-min 2>/dev/null)" != "$MACOSX_DEPLOYMENT_TARGET" ]; then
  rm -rf _build out/mbc out/core/aarch64-apple-darwin
  mkdir -p _build && echo "$MACOSX_DEPLOYMENT_TARGET" > _build/.macos-min
fi
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$A/out/core-target}-macos$MACOSX_DEPLOYMENT_TARGET

sign() {
  local t=$(now)
  # signed: still.fail's identity (as its desktop app: no hardened runtime, not notarized), else ad hoc
  codesign --force --sign "${MAC_SIGN_IDENTITY:--}" --timestamp=none "$APPDIR"
  codesign --verify --deep --strict --verbose=2 "$APPDIR" 2>&1 | sed 's/^/codesign: /'
  codesign -dv "$APPDIR" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier|Signature|Format)=' | sed 's/^/codesign: /'
  spctl --assess --type execute -vv "$APPDIR" 2>&1 | sed 's/^/spctl: /' || true
  rm -f "$ZIP"
  (cd "$OUT" && ditto -c -k --sequesterRsrc --keepParent "$NAME.app" "$(basename "$ZIP")")
  echo "mac-app.sh: $(basename "$ZIP") $(wc -c < "$ZIP" | tr -d ' ') bytes, signed and zipped in $(secs $t) s"
}
if [ "${1:-build}" = sign ]; then
  [ -d "$APPDIR" ] || { echo "mac-app.sh: no app (mac-app.sh build)" >&2; exit 1; }
  sign
  exit 0
fi

# the core's parts: its Rust shell (linked in) and its script (carried)
if [ "${MBUI_CORE_FRESH:-}" = 1 ] || [ ! -f out/core/aarch64-apple-darwin/libstillfail_shell.a ]; then bash "$D/core.sh" shell > "$OUT/shell.log" 2>&1 || { tail -30 "$OUT/shell.log"; exit 1; }; fi
if [ "${MBUI_CORE_FRESH:-}" = 1 ] || [ ! -f out/core/core.js ]; then bash "$D/core.sh" bundle > "$OUT/bundle.log" 2>&1 || { tail -30 "$OUT/bundle.log"; exit 1; }; fi
t1=$(now)
APP=stillfail MODE=release bash "$D/mac.sh" build > "$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; exit 1; }
if grep -q 'built for newer macOS version' "$OUT/build.log"; then
  grep 'built for newer macOS version' "$OUT/build.log" | head -5 >&2
  echo "mac-app.sh: something was built for a newer macOS than $MACOSX_DEPLOYMENT_TARGET" >&2; exit 1
fi
BIN=$A/_build/native/release/build/stillfail/stillfail/stillfail.exe
t2=$(now)

# the icon, made once for each version of its script
ICON=$OUT/AppIcon-$(shasum -a 256 "$D/mac-icon.swift" | cut -c1-12).icns
[ -f "$ICON" ] || swift "$D/mac-icon.swift" "$ICON" > /dev/null

rm -rf "$APPDIR" "$ZIP"
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"
cp "$BIN" "$APPDIR/Contents/MacOS/$EXE"
cp out/core/core.js "$APPDIR/Contents/Resources/core.js"
cp "$ICON" "$APPDIR/Contents/Resources/AppIcon.icns"
# the oldest macOS the program runs on, as it was linked: the one asked for
MINOS=$(otool -l "$BIN" | awk '/LC_BUILD_VERSION/ { b = 1 } b && $1 == "minos" { print $2; exit }')
[ "$MINOS" = "$MACOSX_DEPLOYMENT_TARGET" ] || { echo "mac-app.sh: linked for macOS $MINOS, not $MACOSX_DEPLOYMENT_TARGET" >&2; exit 1; }
python3 - "$APPDIR/Contents/Info.plist" "$N" "${MINOS:-13.0}" "$NAME" "$EXE" <<'PY'
import plistlib, sys
path, n, minos, name, exe = sys.argv[1:6]
plistlib.dump({
    "CFBundleIdentifier": "fail.still.mbui",
    "CFBundleName": name,
    "CFBundleDisplayName": name,
    "CFBundleExecutable": exe,
    "CFBundleIconFile": "AppIcon",
    "CFBundlePackageType": "APPL",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleShortVersionString": "0.1." + n,
    "CFBundleVersion": n,
    "CFBundleDevelopmentRegion": "zh_CN",
    "LSMinimumSystemVersion": minos,
    "LSApplicationCategoryType": "public.app-category.developer-tools",
    "NSPrincipalClass": "NSApplication",
    "NSHighResolutionCapable": True,
    "NSSupportsAutomaticGraphicsSwitching": True,
    # the core reaches stations on the local network directly when it can (as still.fail's desktop app says it)
    "NSLocalNetworkUsageDescription": "still.fail mbui connects straight to your stations on the local network when it can.",
}, open(path, "wb"))
PY
plutil -lint "$APPDIR/Contents/Info.plist" > /dev/null

# ad hoc for now: `sign` after (still.fail's identity in CI)
codesign --force --sign - --timestamp=none "$APPDIR"
echo "mac-app.sh: $NAME.app 0.1.$N in $(secs $t0) s: the core's parts $(python3 -c "print(f'{$t1-$t0:.1f}')") s," \
  "the app $(python3 -c "print(f'{$t2-$t1:.1f}')") s, the bundle $(secs $t2) s"
[ "${1:-}" = build ] || sign
