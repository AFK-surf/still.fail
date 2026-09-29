#!/bin/sh
# Builds the desktop app for macOS arm64, signed with the Apple Development certificate in the login keychain
# (so macOS keeps its Local Network grant across updates), into out/mac-arm64/still.fail.app:
# the core (client/node) as build/stillfail_core.node, the web app (`pnpm run
# build:cloud`, dist/cloud-web) as build/web, a
# station (scripts/station-bundle.sh) as build/station, the app's own code as
# build/app, then electron-builder puts them together.
# CARGO_TARGET_DIR is honoured. SKIP_WEB=1 takes dist/cloud-web and dist/admin as they are. SKIP_STATION=1 leaves the station out (the app then runs none). DEV=1 stops at build/: no packing, no
# signing, for Electron's own app to run as it is (dev.sh).
# Packed, the app is also zipped (stillfail-<version>-arm64-mac.zip) with stillfail-mac.yml beside it in out/: what
# scripts/release.sh desktop publishes for the apps' updater (main.ts, keepUpdated). Its version is 0.1.<the commits
# in the history>, each release's higher than the one before it.
# BRIDGE=1 packs the same app under the bundle id from before the rename (dev.ember.desktop), as
# ember-<version>-arm64-mac.zip with latest-mac.yml: what installed apps from before the rename update to, and which
# then moves itself to the app under the new id (src/bridge.ts).
set -eu
# A non-login shell (ssh studio …) has none of these on its PATH.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/Library/pnpm:$HOME/.local/node-v24.15.0-darwin-arm64/bin:$PATH"
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
target=${CARGO_TARGET_DIR:-$root/client/target}
(cd "$root/client" && cargo build -p stillfail-core-node --release --target aarch64-apple-darwin)
# The web app carries PostHog when its key is at hand (docs/telemetry.md), as the cloud's does.
deploy="$HOME/stillfail-deploy"; [ -d "$deploy" ] || deploy="$HOME/ember-deploy"
posthog="$deploy/posthog.json"
[ -n "${SKIP_WEB:-}" ] || (cd "$root" && if [ -f "$posthog" ]; then STILLFAIL_POSTHOG="$posthog" pnpm run build:cloud; else pnpm run build:cloud; fi)
# The station's own page (dist/admin) and stillfail-station, which keeps its target in mesh/.
[ -n "${SKIP_WEB:-}${SKIP_STATION:-}" ] || (cd "$root" && pnpm build)
[ -n "${SKIP_STATION:-}" ] || (cd "$root/mesh" && env -u CARGO_TARGET_DIR cargo build --release -p stillfail-station)
rm -rf "$here/build" "$here/out"
mkdir -p "$here/build/station"
[ -n "${SKIP_STATION:-}" ] || sh "$root/scripts/station-bundle.sh" "$here/build/station"
cp "$target/aarch64-apple-darwin/release/libstillfail_core_node.dylib" "$here/build/stillfail_core.node"
rsync -a "$root/dist/cloud-web/" "$here/build/web/"
cd "$here"
# electron-builder packs the Electron that electron's install script fetches (pnpm may have skipped it).
[ -d node_modules/electron/dist ] || node node_modules/electron/install.js
pnpm exec esbuild src/main.ts src/core.ts src/preload.ts --bundle --platform=node --format=cjs --external:electron --outdir=build/app --log-level=warning
# The page marking in a preview's frame (web/src/annotate/frame.ts), which main.ts serves as its /_ember/annotate.js.
pnpm exec esbuild "$root/web/src/annotate/frame.ts" --bundle --format=iife --minify --outfile=build/app/annotate.js --log-level=warning
[ -z "${DEV:-}" ] || { echo "$here/build"; exit 0; }
version="0.1.$(git -C "$root" rev-list --count HEAD)"
if [ -n "${BRIDGE:-}" ]; then
  # shellcheck disable=SC2016 # electron-builder expands these itself
  pnpm exec electron-builder --mac --arm64 --publish never -c.extraMetadata.version="$version" \
    -c.appId=dev.ember.desktop -c.publish.channel=latest -c.mac.artifactName='ember-${version}-${arch}-mac.${ext}'
else
  pnpm exec electron-builder --mac --arm64 --publish never -c.extraMetadata.version="$version"
fi
ls -d "$here/out/mac-arm64/still.fail.app"
