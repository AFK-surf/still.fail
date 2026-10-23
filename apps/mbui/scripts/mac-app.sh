#!/bin/bash
# still.fail mbui on macOS as an app: out/mac/still.fail mbui.app (fail.still.mbui; arm64, as still.fail's desktop app
# ships), its zip beside it. The app is APP=stillfail's release build (scripts/mac.sh) with what it carries: the core's
# bytecode (Resources/core.hbc, which the core host finds in the app: src/host/apple_core.mm), the desktop's dock
# (Resources/dock/StillfailDock, the desktop app's helper) and Hermes
# (Frameworks/hermes.framework, React Native 0.81.4's, as Android's; scripts/core.sh hermes-apple), its icon
# (scripts/mac-icon.swift), an Info.plist of its own. Signed with MAC_SIGN_IDENTITY (CI: still.fail's, imported by
# .github/mac_signing.py), else ad hoc; checked with codesign's strict verify. Signed with a Developer ID, it is
# notarized and its ticket stapled before it is zipped (mac_signing.py notarize): Gatekeeper lets it open downloaded.
#   apps/mbui/scripts/mac-app.sh            build and bundle it, then sign it (below)
#   apps/mbui/scripts/mac-app.sh build      build and bundle it only (signed ad hoc)
#   apps/mbui/scripts/mac-app.sh sign       sign it (MAC_SIGN_IDENTITY, else ad hoc), check it, zip it:
#                                           out/mac/stillfail-mbui-<n>-arm64-mac.zip (CI: under .github/mac_signing.py,
#                                           which holds the signing lock only for this)
# The oldest macOS it runs on: still.fail's desktop app's (Electron's: 12.0), MACOSX_DEPLOYMENT_TARGET for clang and
# cargo alike, and its Info.plist's LSMinimumSystemVersion; an object built for a newer one fails the build.
# MBUI_BUILD: the build's number (default git rev-list --count HEAD of still.fail); MBUI_CORE_FRESH=1 makes the core's
# shell again (cargo decides what is out of date), else only when missing; the engine and core.hbc are made when stale
# (scripts/core.sh apple).
set -eo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
now() { python3 -c 'import time;print(time.time())'; }
secs() { python3 -c "print(f'{$(now)-$1:.1f}')"; }
N=${MBUI_BUILD:-$(git -C "$EMBER" rev-list --count HEAD 2>/dev/null || echo 1)}
# MBUI_VARIANT, which app it is built as (as Android's apk.json variants are): mbui (the default) still.fail mbui, an app
# beside still.fail's desktop app (fail.still.mbui, its feed mac/mbui); stable and beta still.fail's desktop app itself,
# to take its place: Electron's ids, names and links (apps/desktop/package.json, build.sh), so that app's updater takes
# it and it keeps that app's data, sign-in and sealed keys where they were (src/sfcore/apple_engine.m, src/host/
# apple_core.mm electron_sealed); their feed mac (the beta's core asks mac/beta, as still.fail's beta builds do).
case "${MBUI_VARIANT:-mbui}" in
  mbui) ID=fail.still.mbui NAME="still.fail mbui" FEED=mac/mbui OWN= BETA= SCHEMES=() ZIP_NAME=stillfail-mbui ;;
  stable) ID=fail.still.desktop NAME=still.fail FEED=mac OWN=1 BETA= SCHEMES=(stillfail ember) ZIP_NAME=stillfail ;;
  beta) ID=fail.still.desktop.beta NAME=youdid.wtf FEED=mac OWN=1 BETA=1 SCHEMES=(stillfail-beta) ZIP_NAME=stillfail-beta ;;
  *) echo "mac-app.sh: MBUI_VARIANT is mbui, stable or beta, not $MBUI_VARIANT" >&2; exit 1 ;;
esac
OUT=$A/out/mac
APPDIR="$OUT/$NAME.app"
ZIP=$OUT/$ZIP_NAME-$N-arm64-mac.zip
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
  # signed: still.fail's identity, else ad hoc; what it carries (Hermes's framework) first. A Developer ID's signature
  # is what notarization takes: the hardened runtime and Apple's timestamp.
  local how=(--timestamp=none)
  case "${MAC_SIGN_IDENTITY:-}" in "Developer ID Application:"*) how=(--options runtime --timestamp) ;; esac
  codesign --force --sign "${MAC_SIGN_IDENTITY:--}" "${how[@]}" "$APPDIR/Contents/Frameworks/hermes.framework"
  codesign --force --sign "${MAC_SIGN_IDENTITY:--}" "${how[@]}" "$APPDIR/Contents/Resources/dock/StillfailDock"
  codesign --force --sign "${MAC_SIGN_IDENTITY:--}" "${how[@]}" "$APPDIR"
  codesign --verify --deep --strict --verbose=2 "$APPDIR" 2>&1 | sed 's/^/codesign: /'
  codesign -dvv "$APPDIR" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier|Signature|Format)=' | sed 's/^/codesign: /'
  case "${MAC_SIGN_IDENTITY:-}" in "Developer ID Application:"*) python3 "$EMBER/.github/mac_signing.py" notarize "$APPDIR" ;; esac
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

# the core's parts: its Rust shell and its engine (linked in), Hermes and its bytecode (carried)
if [ "${MBUI_CORE_FRESH:-}" = 1 ] || [ ! -f out/core/aarch64-apple-darwin/libstillfail_shell.a ]; then bash "$D/core.sh" shell > "$OUT/shell.log" 2>&1 || { tail -30 "$OUT/shell.log"; exit 1; }; fi
bash "$D/core.sh" apple aarch64-apple-darwin > "$OUT/core.log" 2>&1 || { tail -30 "$OUT/core.log"; exit 1; }
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
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources" "$APPDIR/Contents/Frameworks"
cp "$BIN" "$APPDIR/Contents/MacOS/$EXE"
# Hermes from the app's Frameworks (@executable_path/../Frameworks), not from the build's tree (the other rpath, gone)
install_name_tool -delete_rpath @executable_path/../../../../../../out/core/hermes/Library/Frameworks/macosx "$APPDIR/Contents/MacOS/$EXE"
ditto out/core/hermes/Library/Frameworks/macosx/hermes.framework "$APPDIR/Contents/Frameworks/hermes.framework"
cp out/core/core.hbc "$APPDIR/Contents/Resources/core.hbc"
# the desktop's dock (apps/desktop/dock, docs/desktop-dock.md): the desktop app's SwiftUI helper, prebuilt (scripts/native.ts
# dock: fetched, never built here), started by the app's host (src/host/mac_app.m dock_spawn)
DOCK=$(node "$EMBER/scripts/native.ts" fetch dock darwin-arm64 > /dev/null && node "$EMBER/scripts/native.ts" file dock darwin-arm64)
mkdir -p "$APPDIR/Contents/Resources/dock"
cp "$DOCK" "$APPDIR/Contents/Resources/dock/StillfailDock"
cp "$ICON" "$APPDIR/Contents/Resources/AppIcon.icns"
# the oldest macOS the program runs on, as it was linked: the one asked for
MINOS=$(otool -l "$BIN" | awk '/LC_BUILD_VERSION/ { b = 1 } b && $1 == "minos" { print $2; exit }')
[ "$MINOS" = "$MACOSX_DEPLOYMENT_TARGET" ] || { echo "mac-app.sh: linked for macOS $MINOS, not $MACOSX_DEPLOYMENT_TARGET" >&2; exit 1; }
PLIST=$APPDIR/Contents/Info.plist
plutil -create xml1 "$PLIST"
put() { plutil -insert "$1" "$2" "$3" "$PLIST"; }
put CFBundleIdentifier -string "$ID"
put CFBundleName -string "$NAME"
put CFBundleDisplayName -string "$NAME"
put CFBundleExecutable -string "$EXE"
put CFBundleIconFile -string AppIcon
put CFBundlePackageType -string APPL
put CFBundleInfoDictionaryVersion -string 6.0
put CFBundleShortVersionString -string "0.1.$N"
put CFBundleVersion -string "$N"
put CFBundleDevelopmentRegion -string zh_CN
put LSMinimumSystemVersion -string "${MINOS:-13.0}"
put LSApplicationCategoryType -string public.app-category.developer-tools
put NSPrincipalClass -string NSApplication
put NSHighResolutionCapable -bool YES
put NSSupportsAutomaticGraphicsSwitching -bool YES
# the core reaches stations on the local network directly when it can (as still.fail's desktop app says it)
put NSLocalNetworkUsageDescription -string "$NAME connects straight to your stations on the local network when it can."
# where its newer builds come from (src/stillfail main: MBUI_UPDATE_FEED; the host installs them: mac_app.m Updates),
# the feed beta.sh mac publishes; built in still.fail's desktop app's place, still.fail's own (the device named as that
# app named it: src/sfcore/signin.mbt MBUI_OWN), the beta's core its beta's (MBUI_BETA). The system gives these to the
# app opened from the Finder, the Dock or `open`.
plutil -insert LSEnvironment -dictionary "$PLIST"
put LSEnvironment.MBUI_UPDATE_FEED -string "$FEED"
[ -z "$OWN" ] || put LSEnvironment.MBUI_OWN -string 1
[ -z "$BETA" ] || put LSEnvironment.MBUI_BETA -string 1
# the links that open it (stillfail://o/…, as still.fail's desktop app takes them: mac_app.m, then sfapp's links)
if [ ${#SCHEMES[@]} -gt 0 ]; then
  plutil -insert CFBundleURLTypes -array "$PLIST"
  plutil -insert CFBundleURLTypes.0 -dictionary "$PLIST"
  put CFBundleURLTypes.0.CFBundleURLName -string "$NAME"
  plutil -insert CFBundleURLTypes.0.CFBundleURLSchemes -array "$PLIST"
  for i in "${!SCHEMES[@]}"; do put "CFBundleURLTypes.0.CFBundleURLSchemes.$i" -string "${SCHEMES[$i]}"; done
fi
plutil -lint "$PLIST" > /dev/null

# ad hoc for now: `sign` after (still.fail's identity in CI)
codesign --force --sign - --timestamp=none "$APPDIR/Contents/Frameworks/hermes.framework"
codesign --force --sign - --timestamp=none "$APPDIR/Contents/Resources/dock/StillfailDock"
codesign --force --sign - --timestamp=none "$APPDIR"
echo "mac-app.sh: $NAME.app 0.1.$N in $(secs $t0) s: the core's parts $(python3 -c "print(f'{$t1-$t0:.1f}')") s," \
  "the app $(python3 -c "print(f'{$t2-$t1:.1f}')") s, the bundle $(secs $t2) s"
[ "${1:-}" = build ] || sign
