#!/bin/sh
# Lays out the still.fail station's release in DIR/stillfail, from what is built here (dist/admin by
# scripts/posthog-key.ts: only the PostHog key the station reports errors with, posthog.json, when $STILLFAIL_POSTHOG
# names one; stillfail-station by cargo in mesh/), for PLATFORM (default: this machine's). scripts/release.sh packs it for install.sh; the desktop app
# (apps/desktop/build.sh) carries it and runs it itself. The layout is the clone's:
#   stillfail/{bin/stillfail, dist/admin/, mesh/target/release/stillfail-station, VERSION, BUILD}
# with the names of before the rename as links to the new ones (bin/ember, mesh/target/release/ember-station), for
# what still runs them by those (scripts, launchers, a service written before the update).
# dist/admin held the station's own page once; a station serves none now, but the directory stays where it was (the
# station reads dist/admin/posthog.json, and finds its release as dist/admin's parent's parent).
# VERSION is the commit; BUILD the commits in its history, the station's version as 0.1.<BUILD> (the apps' numbering).
# For Linux (linux-x64, linux-arm64), from a Mac: stillfail-station as scripts/linux-station.sh builds it.
#   station-bundle.sh DIR [darwin-arm64|linux-x64|linux-arm64]
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: station-bundle.sh DIR [PLATFORM]}
platform=${2:-}
# Written afresh here, so a release never carries what an older build left in dist/admin (its page), nor an old key.
node "$root/scripts/posthog-key.ts" >&2
case "$platform" in
  ""|darwin-arm64) station="$root/mesh/target/release/stillfail-station" ;;
  linux-x64|linux-arm64) station="$("$root/scripts/linux-station.sh" "$platform")" ;;
  *) echo "no such platform: $platform" >&2; exit 1 ;;
esac
[ -x "$station" ] || { echo "stillfail-station is missing: cargo build --release in mesh/" >&2; exit 1; }
app="$out/stillfail"
rm -rf "$app"
mkdir -p "$app/bin" "$app/mesh/target/release" "$app/dist"
cp "$root/bin/stillfail" "$app/bin/"
ln -s stillfail "$app/bin/ember"
cp -R "$root/dist/admin" "$app/dist/admin"
cp "$station" "$app/mesh/target/release/stillfail-station"
ln -s stillfail-station "$app/mesh/target/release/ember-station"
git -C "$root" rev-parse HEAD > "$app/VERSION"
git -C "$root" rev-list --count HEAD > "$app/BUILD"
