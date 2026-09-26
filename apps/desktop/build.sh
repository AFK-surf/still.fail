#!/bin/sh
# Builds the desktop app for macOS arm64, unsigned, into out/mac-arm64/ember.app:
# the core (client/node) as build/ember_core.node, the web app (`pnpm run
# build:cloud`, dist/cloud-app without the admin's console) as build/web, the
# app's own code as build/app, then electron-builder puts them together.
# CARGO_TARGET_DIR is honoured. SKIP_WEB=1 takes dist/cloud-app as it is.
set -eu
export PATH="$HOME/.cargo/bin:$PATH"
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
target=${CARGO_TARGET_DIR:-$root/client/target}
(cd "$root/client" && cargo build -p ember-core-node --release --target aarch64-apple-darwin)
[ -n "${SKIP_WEB:-}" ] || (cd "$root" && pnpm run build:cloud)
rm -rf "$here/build" "$here/out"
mkdir -p "$here/build"
cp "$target/aarch64-apple-darwin/release/libember_core_node.dylib" "$here/build/ember_core.node"
rsync -a --exclude admin-app "$root/dist/cloud-app/" "$here/build/web/"
cd "$here"
# electron-builder packs the Electron that electron's install script fetches (pnpm may have skipped it).
[ -d node_modules/electron/dist ] || node node_modules/electron/install.js
pnpm exec esbuild src/main.ts src/core.ts src/preload.ts --bundle --platform=node --format=cjs --external:electron --outdir=build/app --log-level=warning
pnpm exec electron-builder --mac --arm64 --publish never
ls -d "$here/out/mac-arm64/ember.app"
