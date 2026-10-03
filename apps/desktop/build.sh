#!/bin/sh
# Builds the desktop app for macOS arm64, signed with the Apple Development certificate in the login keychain
# (so macOS keeps its Local Network grant across updates).
# Only the Mach-O files are signed one by one (package.json build.mac.signIgnore skips the rest: Electron's .pak and
# .dat, the web app's assets, which the app's own signature seals anyway); signing each, with Apple's timestamp, made a
# release take some fifty minutes.
# Into out/mac-arm64/still.fail.app:
# the core (client/core-ts, bundled as build/app/core-ts.js) with its iroh (station/native/mesh's addon) as
# build/mesh.node, the web app (`pnpm run
# build:cloud`, dist/cloud-web) as build/web, a
# station (scripts/station-bundle.sh) as build/station, the app's own code as
# build/app, then electron-builder puts them together.
# CARGO_TARGET_DIR is honoured (for the mesh addon). SKIP_WEB=1 takes dist/cloud-web and dist/admin as they are. SKIP_STATION=1 leaves the station out (the app then runs none). DEV=1 stops at build/: no packing, no
# signing, for Electron's own app to run as it is (dev.sh).
# UNSIGNED=1 makes either channel's package without the maintainer's signing certificate, for local testing.
# Packed, the app is also zipped (stillfail-<version>-arm64-mac.zip) with stillfail-mac.yml beside it in out/: what
# scripts/release.sh desktop publishes for the apps' updater (main.ts, keepUpdated). Its version is 0.1.<the commits
# in the history>, each release's higher than the one before it.
# --beta (or BETA=1) builds the beta app instead: 「youdid.wtf」 (fail.still.desktop.beta), beside the released one, with
# its own userData and link scheme (stillfail-beta://), its core saying it is a beta app and its updates on the
# stillfail-beta channel (main.ts BETA): out/mac-arm64/youdid.wtf.app, zipped as stillfail-beta-<version>-arm64-mac.zip
# with stillfail-beta-mac.yml beside it.
set -eu
[ "${1:-}" = "--beta" ] && BETA=1
beta=${BETA:-}
# A non-login shell (ssh studio …) has none of these on its PATH.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/Library/pnpm:$HOME/.local/node-v24.15.0-darwin-arm64/bin:$PATH"
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
target=${CARGO_TARGET_DIR:-$root/station/native/mesh/target}
(cd "$root/station/native/mesh" && CARGO_TARGET_DIR="$target" cargo build --release --target aarch64-apple-darwin)
(cd "$root/client/core-ts" && pnpm install --frozen-lockfile --silent)
# The web app carries PostHog when its key is at hand (docs/telemetry.md), as the cloud's does.
deploy="$HOME/stillfail-deploy"; [ -d "$deploy" ] || deploy="$HOME/ember-deploy"
posthog="$deploy/posthog.json"
[ -n "${SKIP_WEB:-}" ] || (cd "$root" && if [ -f "$posthog" ]; then STILLFAIL_POSTHOG="$posthog" pnpm run build:cloud; else pnpm run build:cloud; fi)
# The station's dist/admin (only the PostHog key its error reports use: `pnpm build` without building the core again)
# and stillfail-station, which keeps its target in mesh/.
[ -n "${SKIP_WEB:-}${SKIP_STATION:-}" ] || (cd "$root" && if [ -f "$posthog" ]; then STILLFAIL_POSTHOG="$posthog" node scripts/posthog-key.ts; else node scripts/posthog-key.ts; fi)
[ -n "${SKIP_STATION:-}" ] || (cd "$root/mesh" && env -u CARGO_TARGET_DIR cargo build --release -p stillfail-station)
rm -rf "$here/build" "$here/out"
mkdir -p "$here/build/station"
[ -n "${SKIP_STATION:-}" ] || sh "$root/scripts/station-bundle.sh" "$here/build/station"
cp "$target/aarch64-apple-darwin/release/libstillfail_mesh.dylib" "$here/build/mesh.node"
rsync -a "$root/dist/cloud-web/" "$here/build/web/"
cd "$here"
# electron-builder packs the Electron that electron's install script fetches (pnpm may have skipped it).
[ -d node_modules/electron/dist ] || node node_modules/electron/install.js
pnpm exec esbuild src/main.ts src/core.ts src/preload.ts --bundle --platform=node --format=cjs --external:electron --outdir=build/app --log-level=warning \
  ${beta:+--define:process.env.STILLFAIL_CHANNEL='"beta"'}
# The page marking in a preview's frame (web/src/annotate/frame.ts), which main.ts serves as its /_ember/annotate.js.
# The core: client/core-ts's Node host, required by core.js (its addon and ws's optional natives are not bundled).
pnpm exec esbuild "$root/client/core-ts/src/hosts/node.ts" --bundle --platform=node --format=cjs --target=node22 --outfile=build/app/core-ts.js \
  --external:electron --external:bufferutil --external:utf-8-validate --log-level=error
pnpm exec esbuild "$root/web/src/annotate/frame.ts" --bundle --format=iife --minify --outfile=build/app/annotate.js --log-level=warning
[ -z "${DEV:-}" ] || { echo "$here/build"; exit 0; }
version="0.1.$(git -C "$root" rev-list --count HEAD)"
set --
[ -z "${UNSIGNED:-}" ] || set -- -c.mac.identity=null
if [ -z "$beta" ]; then
  pnpm exec electron-builder --mac --arm64 --publish never -c.extraMetadata.version="$version" "$@"
  ls -d "$here/out/mac-arm64/still.fail.app"
else
  # package.json's build, made the beta app's (the name the app and its userData go by is its productName).
  node -e '
    const [version, out] = process.argv.slice(1);
    const pkg = JSON.parse(require("fs").readFileSync("package.json", "utf8"));
    const name = "youdid.wtf";
    const b = pkg.build;
    b.appId = "fail.still.desktop.beta";
    b.productName = name;
    b.extraMetadata = { ...b.extraMetadata, version, productName: name };
    b.protocols = [{ name, schemes: ["stillfail-beta"] }];
    b.mac = { ...b.mac, extendInfo: { ...b.mac.extendInfo, CFBundleName: name, CFBundleDisplayName: name, NSLocalNetworkUsageDescription: b.mac.extendInfo.NSLocalNetworkUsageDescription.replace("still.fail", name) }, artifactName: "stillfail-beta-${version}-${arch}-mac.${ext}", icon: "icon-beta.png" };
    b.publish = { ...b.publish, channel: "stillfail-beta" };
    require("fs").writeFileSync(out, JSON.stringify(b, null, 2));
  ' "$version" build/builder-beta.json
  pnpm exec electron-builder --mac --arm64 --publish never --config build/builder-beta.json "$@"
  ls -d "$here/out/mac-arm64/youdid.wtf.app"
fi
