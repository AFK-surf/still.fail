#!/bin/bash
# Builds the app for the iOS simulator on a Mac with Xcode (studio): the core (scripts/core-ios.sh) when it is not
# there yet, the native project (expo prebuild, pods), then the Release app with the JS in it, arm64 only.
#   bash scripts/ios.sh [--debug] [derived-data-dir]     (default ../ios-dd beside the app: outside ios/build, which
#                                                         holds the codegen pod install made)
# Prints the .app's path last.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
config=Release; [ "${1:-}" = --debug ] && { config=Debug; shift; }
dd=${1:-$here/../ios-dd}
cd "$here"
[ -d node_modules ] || npm install --legacy-peer-deps --silent
# The web build makes it (the iroh package's build time); the type checker reads it through web/src/core/built.ts.
[ -f ../../web/src/core/iroh-pkg/built.js ] || { mkdir -p ../../web/src/core/iroh-pkg; echo "export const BUILT_AT = 0;" > ../../web/src/core/iroh-pkg/built.js; echo "export declare const BUILT_AT: number;" > ../../web/src/core/iroh-pkg/built.d.ts; }
p=modules/stillfail-core/ios/prebuilt
[ -d $p/StillfailShell.xcframework ] && [ -f $p/core.hbc ] || bash scripts/core-ios.sh
npx expo prebuild -p ios --no-install > /dev/null
# Studio's way to Maven sometimes drops the TLS handshake, and CocoaPods then quietly builds Folly, fmt and the rest from
# source instead of React Native's prebuilt ones (fmt 11 does not build with Xcode 26.4): again until it takes them.
cd ios
for n in 1 2 3; do
  pod install > ../pod.log 2>&1 || { tail -30 ../pod.log; exit 1; }
  [ ! -d Pods/RCT-Folly ] && break
  [ $n -lt 3 ] || { echo "pod install did not take React Native's prebuilt dependencies"; exit 1; }
  echo "pod install without the prebuilt dependencies, again ($n)"; rm -rf Pods
done
w=$(ls -d *.xcworkspace | head -1); s=$(basename "$w" .xcworkspace)
xcodebuild -workspace "$w" -scheme "$s" -configuration $config -sdk iphonesimulator -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$dd" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build > ../xcodebuild.log 2>&1 || { grep -E "error:|Undefined symbol|ld: " ../xcodebuild.log | head -60; tail -20 ../xcodebuild.log; exit 1; }
ls -d "$dd/Build/Products/$config-iphonesimulator/"*.app
