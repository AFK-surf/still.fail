#!/bin/sh
# Lays out ember station's release in DIR/ember, from what is built here (the station page in dist/admin by `pnpm
# build`, ember-station by cargo in mesh/), for PLATFORM (default: this machine's). scripts/release.sh packs it for
# install.sh; the desktop app (apps/desktop/build.sh) carries it and runs it itself. The layout is the clone's:
#   ember/{bin/ember, src/, package.json, node_modules/ (production), dist/admin/, mesh/target/release/ember-station, node/bin/node, VERSION}
# For Linux (linux-x64, linux-arm64), from a Mac: ember-station as scripts/linux-station.sh builds it, and Node's own
# Linux build of the version run here (downloaded once into the build cache). The Node dependencies are plain
# JavaScript, the same everywhere.
#   station-bundle.sh DIR [darwin-arm64|linux-x64|linux-arm64]
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: station-bundle.sh DIR [PLATFORM]}
platform=${2:-}
[ -f "$root/dist/admin/index.html" ] || { echo "dist/admin is missing: run pnpm build first" >&2; exit 1; }
case "$platform" in
  ""|darwin-arm64)
    station="$root/mesh/target/release/ember-station"
    node=$(command -v node) ;;
  linux-x64|linux-arm64)
    station="$("$root/scripts/linux-station.sh" "$platform")"
    node="$("$root/scripts/linux-node.sh" "$platform")" ;;
  *) echo "no such platform: $platform" >&2; exit 1 ;;
esac
[ -x "$station" ] || { echo "ember-station is missing: cargo build --release in mesh/" >&2; exit 1; }
app="$out/ember"
rm -rf "$app"
mkdir -p "$app/node/bin" "$app/mesh/target/release" "$app/dist"
cp "$node" "$app/node/bin/node"
cp -R "$root/src" "$root/bin" "$root/package.json" "$app/"
cp -R "$root/dist/admin" "$app/dist/admin"
cp "$station" "$app/mesh/target/release/"
(cd "$app" && npm install --omit=dev --no-package-lock --no-audit --no-fund --loglevel=error >/dev/null)
git -C "$root" rev-parse HEAD > "$app/VERSION"
