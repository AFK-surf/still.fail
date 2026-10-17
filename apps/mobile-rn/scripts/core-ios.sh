#!/bin/bash
# The core for the RN app on iOS, put where modules/stillfail-core/ios/StillfailCore.podspec picks it up
# (modules/stillfail-core/ios/prebuilt, not committed); run it before `pod install`. On a Mac with Xcode, rustup, Node
# and pnpm (studio):
#   - the Rust shell (client/shell) as a static library for the phone (aarch64-apple-ios) and the simulator
#     (aarch64-apple-ios-sim), in one XCFramework: StillfailShell.xcframework;
#   - the core (client/core-ts) as Hermes bytecode, core.hbc, compiled by the hermesc of the app's React Native (its
#     node_modules, or its npm package as apps/android/build.py fetches one), so it is the bytecode of the Hermes the
#     app runs.
# The Android app's build is not touched: its shell is scripts/native.ts's `shell` part, built on its own.
#   bash scripts/core-ios.sh              # both
#   bash scripts/core-ios.sh shell|core   # one of them
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$here/../.." && pwd)
out="$here/modules/stillfail-core/ios/prebuilt"
what=${1:-all}
mkdir -p "$out"

# The Rust every native part is built with, through rustup's cargo (as scripts/native.ts rustEnv); the app's lowest iOS
# (Expo SDK 54's).
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH" RUSTUP_TOOLCHAIN=1.95.0 CARGO_INCREMENTAL=0 IPHONEOS_DEPLOYMENT_TARGET=15.1
TARGETS="aarch64-apple-ios aarch64-apple-ios-sim"

if [ "$what" = all ] || [ "$what" = shell ]; then
  rustup target add $TARGETS > /dev/null
  # The worktree's own target directory (a vendored crate built from two checkouts in one confuses rustc).
  target="$root/client/target"
  libs=()
  for t in $TARGETS; do
    (cd "$root/client" && CARGO_TARGET_DIR="$target" cargo rustc --locked -p stillfail-shell --lib --crate-type staticlib --target "$t" --release \
      -- --print native-static-libs) 2>&1 | grep -E "native-static-libs|error|warning: unused" || true
    lib="$target/$t/release/libstillfail_shell.a"
    [ -f "$lib" ] || { echo "no $lib" >&2; exit 1; }
    libs+=(-library "$lib")
  done
  rm -rf "$out/StillfailShell.xcframework"
  xcodebuild -create-xcframework "${libs[@]}" -output "$out/StillfailShell.xcframework" > /dev/null
  du -sh "$out/StillfailShell.xcframework"
fi

if [ "$what" = all ] || [ "$what" = core ]; then
  hermesc="$here/node_modules/react-native/sdks/hermesc/osx-bin/hermesc"
  if [ ! -x "$hermesc" ]; then
    rn=$(node -p "require('$here/package.json').dependencies['react-native']")
    cache="${STILLFAIL_BUILD_CACHE:-$HOME/Library/Caches/stillfail-build}/hermesc-$rn"
    hermesc="$cache/package/sdks/hermesc/osx-bin/hermesc"
    if [ ! -x "$hermesc" ]; then
      mkdir -p "$cache"
      (cd "$cache" && npm pack "react-native@$rn" --silent > /dev/null && tar -xzf "react-native-$rn.tgz" package/sdks/hermesc)
    fi
  fi
  (cd "$root/client/core-ts" && pnpm install --frozen-lockfile --silent)
  tmp=$(mktemp -d)
  # hermesc's warnings (each with its line of the minified bundle) said only when it fails.
  (cd "$root/client/core-ts" && HERMESC="$hermesc" node scripts/hermes-bundle.ts "$tmp/core.js" "$out/core.hbc") > "$tmp/log" 2>&1 \
    || { grep -v "^ " "$tmp/log" | tail -30; rm -rf "$tmp"; exit 1; }
  rm -rf "$tmp"
  ls -la "$out/core.hbc"
fi
