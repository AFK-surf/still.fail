#!/bin/bash
# still.fail mbui on macOS as an app: out/mac/still.fail mbui.app (fail.still.mbui; arm64, as still.fail's desktop app
# ships), its zip beside it. The app is APP=stillfail's release build (scripts/mac.sh) with what it carries: the core's
# bytecode (Resources/core.hbc, which the core host finds in the app: src/host/apple_core.mm) and Hermes
# (Frameworks/hermes.framework, React Native 0.81.4's, as Android's; scripts/core.sh hermes-apple), its icon
# (scripts/mac-icon.swift, its variant's), an Info.plist of its own. Signed with MAC_SIGN_IDENTITY (CI: still.fail's,
# imported by .github/mac_signing.py), else ad hoc; checked with codesign's strict verify. Signed with a Developer ID,
# it is notarized before it is zipped (mac_signing.py notarize): Gatekeeper lets it open downloaded. Its ticket is not
# stapled: stapling fetches it from Apple's CloudKit, whose connection from CI's Mac dropped in most of main's runs
# (Error 68, the app notarized), and nothing needs it there: a download is opened online (Gatekeeper asks Apple for the
# ticket then), and the app's own updates are not quarantined.
#   apps/mbui/scripts/mac-app.sh            build and bundle it, then sign it (below)
#   apps/mbui/scripts/mac-app.sh build      build and bundle it only (signed ad hoc)
#   apps/mbui/scripts/mac-app.sh sign       sign it (MAC_SIGN_IDENTITY, else ad hoc), check it, zip it:
#                                           out/mac/stillfail-mbui-<n>-arm64-mac.zip (CI: under .github/mac_signing.py,
#                                           which holds the signing lock only for this)
# The oldest macOS it runs on: still.fail's desktop app's (Electron's: 12.0), MACOSX_DEPLOYMENT_TARGET for clang and
# cargo alike, and its Info.plist's LSMinimumSystemVersion; an object built for a newer one fails the build.
# MBUI_BUILD: the build's number (default git rev-list --count HEAD of still.fail). The core's parts are scripts/core.sh
# apple's: the shell as still.fail's natives have it for its sources (shell-apple), the engine and core.hbc made when
# stale.
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
# apple_core.mm electron_sealed); their feed mac (the beta's core asks mac/beta, as still.fail's beta builds do). The
# beta's core and still.fail mbui's are a beta's (MBUI_BETA): builds of every commit, the test channel's.
case "${MBUI_VARIANT:-mbui}" in
  mbui) ID=fail.still.mbui NAME="still.fail mbui" FEED=mac/mbui OWN= BETA=1 SCHEMES=() ZIP_NAME=stillfail-mbui ;;
  stable) ID=fail.still.desktop NAME=still.fail FEED=mac OWN=1 BETA= SCHEMES=(stillfail ember) ZIP_NAME=stillfail ;;
  beta) ID=fail.still.desktop.beta NAME=youdid.wtf FEED=mac OWN=1 BETA=1 SCHEMES=(stillfail-beta) ZIP_NAME=stillfail-beta ;;
  *) echo "mac-app.sh: MBUI_VARIANT is mbui, stable or beta, not $MBUI_VARIANT" >&2; exit 1 ;;
esac
OUT=$A/out/mac
APPDIR="$OUT/$NAME.app"
ZIP=$OUT/$ZIP_NAME-$N-arm64-mac.zip
# its program: built in the Electron app's place, named as that app's is (its name): the Electron app's updater
# (Squirrel.Mac) names the bundle it puts in place after the new one's program, and would leave the app renamed
EXE=stillfail-mbui
[ -z "$OWN" ] || EXE=$NAME
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
  [ ! -d "$APPDIR/Contents/Frameworks/Squirrel.framework" ] ||
    codesign --force --sign "${MAC_SIGN_IDENTITY:--}" "${how[@]}" "$APPDIR/Contents/Frameworks/Squirrel.framework"
  codesign --force --sign "${MAC_SIGN_IDENTITY:--}" "${how[@]}" "$APPDIR"
  codesign --verify --deep --strict --verbose=2 "$APPDIR" 2>&1 | sed 's/^/codesign: /'
  codesign -dvv "$APPDIR" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier|Signature|Format)=' | sed 's/^/codesign: /'
  case "${MAC_SIGN_IDENTITY:-}" in "Developer ID Application:"*) python3 "$EMBER/.github/mac_signing.py" notarize "$APPDIR" --no-staple ;; esac
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

# the app with the core's parts: its Rust shell and its engine (linked in), Hermes and its bytecode (carried), which
# scripts/mac.sh makes (the bytecode beside the app's compile). (Not `core.sh shell` first when the .a was missing, as
# before: that built the shell with cargo, past its prebuilt part, on every CI run whose Actions cache of out/core
# missed: 253 s of 427, 2026-10-24, 40069429045.)
APP=stillfail MODE=release bash "$D/mac.sh" build > "$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; exit 1; }
if grep -q 'built for newer macOS version' "$OUT/build.log"; then
  grep 'built for newer macOS version' "$OUT/build.log" | head -5 >&2
  echo "mac-app.sh: something was built for a newer macOS than $MACOSX_DEPLOYMENT_TARGET" >&2; exit 1
fi
# (where the build's time went, said: mbc's account of the app's units and its link, the core's parts; the log
# itself kept only for a failure, and the app's 73 s of a release's 185 s Mac job could not be told apart, 2026-10-31)
grep -E '^mbc: |^core\.sh|hermes|^real|took|in [0-9.]+ s' "$OUT/build.log" | cut -c1-220 | head -20 || true
BIN=$A/_build/native/release/build/stillfail/stillfail/stillfail.exe
t2=$(now)

# the icon, the app's own (still.fail's face; youdid.wtf's under its tape; still.fail mbui's still.fail's), made once
# for each version of its script: an Icon Composer document whose tile and face are each appearance's own (the black
# face, the white one on a dark system), compiled by actool into the app's Assets.car, which macOS 26 draws as the
# system's appearance is, the app open or not; and the black face's .icns for the macOS before (CFBundleIconFile).
# actool knows .icon from Xcode 26: the newest Xcode's that does, whichever is selected.
VARIANT=${MBUI_VARIANT:-mbui}
[ "$VARIANT" = beta ] && FACE=beta || FACE=stable
ICON=$OUT/AppIcon-$(shasum -a 256 "$D/mac-icon.swift" | cut -c1-12)-$FACE
[ -f "$ICON.icns" ] || swift "$D/mac-icon.swift" "$FACE" "$ICON.icns" > /dev/null
if [ ! -f "$ICON.assets/Assets.car" ]; then
  ACTOOL=
  for dev in "$(xcode-select -p)" $(ls -d /Applications/Xcode*.app/Contents/Developer 2>/dev/null | sort -rV); do
    v=$(DEVELOPER_DIR=$dev xcrun actool --version 2>/dev/null | awk -F'[<>.]' '/short-bundle-version/ { getline; print $3 }') || true
    if [ "${v:-0}" -ge 26 ] 2>/dev/null; then ACTOOL=$dev; break; fi
  done
  [ -n "$ACTOOL" ] || { echo "mac-app.sh: no Xcode 26 or later's actool here, to compile the app's icon" >&2; exit 1; }
  # (the document named as the icon it is: actool compiles nothing for a name it is not)
  rm -rf "$ICON.assets" && mkdir -p "$ICON.assets"
  swift "$D/mac-icon.swift" --icon "$FACE" "$ICON.assets/AppIcon.icon" > /dev/null
  DEVELOPER_DIR=$ACTOOL xcrun actool "$ICON.assets/AppIcon.icon" --compile "$ICON.assets" --app-icon AppIcon --platform macosx \
    --target-device mac --minimum-deployment-target "$MACOSX_DEPLOYMENT_TARGET" \
    --output-partial-info-plist "$ICON.assets/partial.plist" > "$ICON.assets/actool.log" 2>&1 \
    && [ -f "$ICON.assets/Assets.car" ] || { cat "$ICON.assets/actool.log" >&2; rm -rf "$ICON.assets"; exit 1; }
fi

rm -rf "$APPDIR" "$ZIP"
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources" "$APPDIR/Contents/Frameworks"
cp "$BIN" "$APPDIR/Contents/MacOS/$EXE"
# Only the copies in the app are trimmed, before signing: the build keeps its symbols for diagnostics.
strip -S -x "$APPDIR/Contents/MacOS/$EXE"
# Hermes from the app's Frameworks (@executable_path/../Frameworks), not from the build's tree (the other rpath, gone)
install_name_tool -delete_rpath @executable_path/../../../../../../out/core/hermes/Library/Frameworks/macosx "$APPDIR/Contents/MacOS/$EXE"
ditto out/core/hermes/Library/Frameworks/macosx/hermes.framework "$APPDIR/Contents/Frameworks/hermes.framework"
# The app is arm64 only; the upstream framework also carries x86_64. Keep its versioned layout and exported symbols.
HERMES=$APPDIR/Contents/Frameworks/hermes.framework/Versions/Current/hermes
if [ "$(lipo -archs "$HERMES")" != arm64 ]; then
  lipo "$HERMES" -thin arm64 -output "$HERMES.arm64"
  mv "$HERMES.arm64" "$HERMES"
fi
strip -S -x "$HERMES"
# Built in the Electron app's place: what that app's updater runs out of the app it has put in place to open it
# (src/host/shipit.c), where it runs it: Frameworks/Squirrel.framework/Resources/ShipIt, here the framework's program
SQUIRREL=$APPDIR/Contents/Frameworks/Squirrel.framework
if [ -n "$OWN" ]; then
  mkdir -p "$SQUIRREL/Versions/A/Resources"
  clang -O2 -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" -o "$SQUIRREL/Versions/A/Squirrel" src/host/shipit.c
  ln -s ../Squirrel "$SQUIRREL/Versions/A/Resources/ShipIt"
  plutil -create xml1 "$SQUIRREL/Versions/A/Resources/Info.plist"
  for kv in "CFBundleIdentifier $ID.shipit" "CFBundleExecutable Squirrel" "CFBundleName Squirrel" "CFBundlePackageType FMWK" \
    "CFBundleInfoDictionaryVersion 6.0" "CFBundleShortVersionString 0.1.$N" "CFBundleVersion $N"; do
    plutil -insert "${kv%% *}" -string "${kv#* }" "$SQUIRREL/Versions/A/Resources/Info.plist"
  done
  ln -s A "$SQUIRREL/Versions/Current"
  ln -s Versions/Current/Squirrel "$SQUIRREL/Squirrel"
  ln -s Versions/Current/Resources "$SQUIRREL/Resources"
fi
cp out/core/core.hbc "$APPDIR/Contents/Resources/core.hbc"
cp "$ICON.icns" "$APPDIR/Contents/Resources/AppIcon.icns"
cp "$ICON.assets/Assets.car" "$APPDIR/Contents/Resources/Assets.car"
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
put CFBundleIconName -string AppIcon
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
# app named it: src/sfcore/signin.mbt MBUI_OWN), a core on the test channel a beta's (MBUI_BETA). The system gives these
# to the app opened from the Finder, the Dock or `open`.
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
[ -z "$OWN" ] || codesign --force --sign - --timestamp=none "$SQUIRREL"
codesign --force --sign - --timestamp=none "$APPDIR"
echo "mac-app.sh: $NAME.app 0.1.$N in $(secs $t0) s: the app and the core's parts $(python3 -c "print(f'{$t2-$t0:.1f}')") s," \
  "the bundle $(secs $t2) s"
[ "${1:-}" = build ] || sign
