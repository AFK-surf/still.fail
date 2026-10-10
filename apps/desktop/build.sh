#!/bin/sh
# Builds the desktop app for macOS arm64, signed with the Apple Development certificate in the login keychain
# (so macOS keeps its Local Network grant across updates).
# Only the Mach-O files are signed one by one (package.json build.mac.signIgnore skips the rest: Electron's .pak and
# .dat, the web app's assets, which the app's own signature seals anyway); signing each, with Apple's timestamp, made a
# release take some fifty minutes.
# Into out/mac-arm64/still.fail.app: the core (client/core-ts, bundled as build/app/core-ts.js) with its iroh
# (station/native/mesh's addon) as build/mesh.node, the web app (`pnpm run build:cloud`, dist/cloud-web) as build/web,
# a station (the station in TypeScript with its Node and native parts: scripts/station-bundle.sh) as build/station, the
# app's own code as build/app, then electron-builder puts them together.
# The native parts (the mesh addon, the station's launcher and runner, the web's iroh, the dock) are prebuilt
# (scripts/native.ts): no Rust or Swift is compiled here unless one of them changed and is not published yet.
# SKIP_WEB=1 takes dist/cloud-web as it is. SKIP_STATION=1 leaves the station out (the app then runs none). DEV=1 stops
# at build/: no packing, no signing, for Electron's own app to run as it is (dev.sh).
# UNSIGNED=1 makes either channel's package without the maintainer's signing certificate, for local testing.
# Packed, the app is also zipped (stillfail-<version>-arm64-mac.zip) with stillfail-mac.yml beside it in out/: what
# scripts/release.sh desktop publishes for the apps' updater (main.ts, keepUpdated). Its version is 0.1.<the commits
# in the history>, each release's higher than the one before it.
# --win (or WIN=1) builds it for Windows x64 instead, from the Mac: an NSIS installer (out/stillfail-<version>-x64-win.exe,
# its blockmap and the feed stillfail.yml; with --beta stillfail-beta-…-win.exe and stillfail-beta.yml), not signed
# yet. It carries Windows' station (station-bundle.sh win32-x64), run on its Electron as on the Mac; no dock.
# --beta (or BETA=1) builds the beta app instead: 「youdid.wtf」 (fail.still.desktop.beta), beside the released one, with
# its own userData and link scheme (stillfail-beta://), its core saying it is a beta app and its updates on the
# stillfail-beta channel (main.ts BETA): out/mac-arm64/youdid.wtf.app, zipped as stillfail-beta-<version>-arm64-mac.zip
# with stillfail-beta-mac.yml beside it.
set -eu
for arg; do
  case $arg in
    --beta) BETA=1 ;;
    --win) WIN=1 ;;
    *) echo "build.sh [--beta] [--win]: not $arg" >&2; exit 2 ;;
  esac
done
beta=${BETA:-}
win=${WIN:-}
# A non-login shell (ssh studio …) has none of these on its PATH.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/Library/pnpm:$PATH"
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# The Node the station runs on (.node-version: Electron's), first.
PATH="$(sh "$root/scripts/node-here.sh"):$PATH"
target=darwin-arm64
[ -z "$win" ] || target=win32-x64
mesh=$(node "$root/scripts/native.ts" file mesh "$target")
# The dock (docs/desktop-dock.md), SwiftUI: prebuilt too, built only when its sources changed. macOS's only.
[ -n "$win" ] || dock=$(node "$root/scripts/native.ts" file dock darwin-arm64)
(cd "$root/client/core-ts" && pnpm install --frozen-lockfile --silent)
# The web app carries PostHog when its key is at hand (docs/telemetry.md), as the cloud's does.
deploy="$HOME/stillfail-deploy"; [ -d "$deploy" ] || deploy="$HOME/ember-deploy"
posthog="$deploy/posthog.json"
[ -n "${SKIP_WEB:-}" ] || (cd "$root" && if [ -f "$posthog" ]; then STILLFAIL_POSTHOG="$posthog" pnpm run build:cloud; else pnpm run build:cloud; fi)
# The station, with the PostHog key its error reports use (station-bundle.sh writes dist/admin/posthog.json from
# $STILLFAIL_POSTHOG).
[ -n "${SKIP_STATION:-}" ] || (cd "$root/station" && pnpm install --frozen-lockfile --silent)
rm -rf "$here/build" "$here/out"
mkdir -p "$here/build/station"
if [ -z "${SKIP_STATION:-}" ]; then
  if [ -f "$posthog" ]; then STILLFAIL_POSTHOG="$posthog" sh "$root/scripts/station-bundle.sh" "$here/build/station" "$target"
  else sh "$root/scripts/station-bundle.sh" "$here/build/station" "$target"; fi
fi
cp "$mesh" "$here/build/mesh.node"
mkdir -p "$here/build/dock" && [ -n "$win" ] || cp "$dock" "$here/build/dock/StillfailDock"
rsync -a "$root/dist/cloud-web/" "$here/build/web/"
cd "$here"
# electron-builder packs the Electron that electron's install script fetches (pnpm may have skipped it).
[ -d node_modules/electron/dist ] || node node_modules/electron/install.js
# The app runs its station on its own Electron as Node (src/station.ts), and the station is built and checked on
# .node-version's: the two the same, or the build stops (upgrading Electron, .node-version goes with it).
electron_node=$(ELECTRON_RUN_AS_NODE=1 node_modules/electron/dist/Electron.app/Contents/MacOS/Electron -p process.versions.node)
[ "$electron_node" = "$(cat "$root/.node-version")" ] || { echo "Electron runs Node $electron_node, .node-version says $(cat "$root/.node-version"): make them the same" >&2; exit 1; }
pnpm exec esbuild src/main.ts src/core.ts src/preload.ts --bundle --platform=node --format=cjs --external:electron --outdir=build/app --log-level=warning \
  ${beta:+--define:process.env.STILLFAIL_CHANNEL='"beta"'}
# The page marking in a preview's frame (web/src/annotate/frame.ts), which main.ts serves as its /_ember/annotate.js.
# The core: client/core-ts's Node host, required by core.js (its addon and ws's optional natives are not bundled).
pnpm exec esbuild "$root/client/core-ts/src/hosts/node.ts" --bundle --platform=node --format=cjs --target=node22 --outfile=build/app/core-ts.js \
  --external:electron --external:bufferutil --external:utf-8-validate --log-level=error
pnpm exec esbuild "$root/web/src/annotate/frame.ts" --bundle --format=iife --minify --outfile=build/app/annotate.js --log-level=warning
[ -z "${DEV:-}" ] || { echo "$here/build"; exit 0; }
version="0.1.$(git -C "$root" rev-list --count HEAD)"
# package.json's build, for this one: the beta app's (the name the app and its userData go by is its productName),
# and Windows' (Electron's own for it, which electron-builder fetches: node_modules/electron/dist is the Mac's).
node -e '
  const [version, beta, win, out] = process.argv.slice(1);
  const pkg = JSON.parse(require("fs").readFileSync("package.json", "utf8"));
  const b = pkg.build;
  b.extraMetadata = { ...b.extraMetadata, version };
  if (beta) {
    const name = "youdid.wtf";
    b.appId = "fail.still.desktop.beta";
    b.productName = name;
    b.extraMetadata.productName = name;
    b.protocols = [{ name, schemes: ["stillfail-beta"] }];
    const usage = Object.fromEntries(Object.entries(b.mac.extendInfo).filter(([k]) => k.endsWith("UsageDescription")).map(([k, v]) => [k, v.replace("still.fail", name)]));
    b.mac = { ...b.mac, extendInfo: { ...b.mac.extendInfo, CFBundleName: name, CFBundleDisplayName: name, ...usage }, artifactName: "stillfail-beta-${version}-${arch}-mac.${ext}", icon: "icon-beta.png" };
    b.win = { ...b.win, artifactName: "stillfail-beta-${version}-${arch}-win.${ext}", icon: "icon-beta.png" };
    b.publish = { ...b.publish, channel: "stillfail-beta" };
  }
  // On Windows the package name is the install folder (%LOCALAPPDATA%\Programs\<name>): its own for each app, and not
  // @stillfail/desktop sanitized. Not on macOS, where it names the cache of the updater.
  if (win) {
    delete b.electronDist;
    b.extraMetadata.name = beta ? "stillfail-beta" : "stillfail";
  }
  require("fs").writeFileSync(out, JSON.stringify(b, null, 2));
' "$version" "$beta" "$win" build/builder.json
app=$([ -n "$beta" ] && echo youdid.wtf || echo still.fail)
if [ -n "$win" ]; then
  pnpm exec electron-builder --win --x64 --publish never --config build/builder.json
  ls "$here/out/stillfail${beta:+-beta}-$version-x64-win.exe"
else
  set --
  [ -z "${UNSIGNED:-}" ] || set -- -c.mac.identity=null
  pnpm exec electron-builder --mac --arm64 --publish never --config build/builder.json "$@"
  ls -d "$here/out/mac-arm64/$app.app"
fi
