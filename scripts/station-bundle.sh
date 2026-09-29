#!/bin/sh
# Lays out ember station's release in DIR/ember, from what is built here (the station page in dist/admin by `pnpm
# build`, ember-station by cargo in mesh/), for PLATFORM (default: this machine's). scripts/release.sh packs it for
# install.sh; the desktop app (apps/desktop/build.sh) carries it and runs it itself. The layout is the clone's:
#   ember/{bin/ember, dist/admin/, mesh/target/release/ember-station, VERSION, BUILD}
# VERSION is the commit; BUILD the commits in its history, the station's version as 0.1.<BUILD> (the apps' numbering).
# For Linux (linux-x64, linux-arm64), from a Mac: ember-station as scripts/linux-station.sh builds it.
#   station-bundle.sh DIR [darwin-arm64|linux-x64|linux-arm64]
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: station-bundle.sh DIR [PLATFORM]}
platform=${2:-}
[ -f "$root/dist/admin/index.html" ] || { echo "dist/admin is missing: run pnpm build first" >&2; exit 1; }
case "$platform" in
  ""|darwin-arm64) station="$root/mesh/target/release/ember-station" ;;
  linux-x64|linux-arm64) station="$("$root/scripts/linux-station.sh" "$platform")" ;;
  *) echo "no such platform: $platform" >&2; exit 1 ;;
esac
[ -x "$station" ] || { echo "ember-station is missing: cargo build --release in mesh/" >&2; exit 1; }
app="$out/ember"
rm -rf "$app"
mkdir -p "$app/bin" "$app/mesh/target/release" "$app/dist"
cp "$root/bin/ember" "$app/bin/"
cp -R "$root/dist/admin" "$app/dist/admin"
cp "$station" "$app/mesh/target/release/"
git -C "$root" rev-parse HEAD > "$app/VERSION"
git -C "$root" rev-list --count HEAD > "$app/BUILD"
