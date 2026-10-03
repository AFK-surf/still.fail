#!/bin/sh
# Lays out the still.fail station's release in DIR/stillfail, from what is built here (dist/admin by
# scripts/posthog-key.ts: only the PostHog key the station reports errors with, posthog.json, when $STILLFAIL_POSTHOG
# names one; stillfail-station by cargo in mesh/, or $STILLFAIL_STATION_RS: the prebuilt one, scripts/native.ts file
# station-rs), for PLATFORM (default: this machine's). scripts/release.sh packs it for install.sh; the desktop app
# (apps/desktop/build.sh) carries it and runs it itself. The layout is the clone's:
#   stillfail/{bin/stillfail, dist/admin/, mesh/target/release/stillfail-station, VERSION, BUILD}
# with the names of before the rename as links to the new ones (bin/ember, mesh/target/release/ember-station), for
# what still runs them by those (scripts, launchers, a service written before the update).
# dist/admin held the station's own page once; a station serves none now, but the directory stays where it was (the
# station reads dist/admin/posthog.json, and finds its release as dist/admin's parent's parent).
# VERSION is the commit; BUILD the commits in its history, the station's version as 0.1.<BUILD> (the apps' numbering).
# For Linux (linux-x64, linux-arm64), from a Mac: stillfail-station as scripts/linux-station.sh builds it.
#   station-bundle.sh DIR [darwin-arm64|linux-x64|linux-arm64]
# STILLFAIL_STATION=ts: the station in TypeScript instead (docs/station-ts.md), in the same layout, so the installer,
# bin/stillfail, the desktop app and the services run it as they run the Rust one: mesh/target/release/stillfail-station
# is its launcher (same command line), and beside the clone's layout
#   station/{main.js, read/worker.js, skills/, mesh.node, stillfail-runner}   (the station; its native parts prebuilt:
#                                                                         scripts/native.ts, parts launcher, mesh, runner)
#   node/bin/node                                                         (the Node it runs on, NODE_VERSION's)
# The Node is the release's own: the agents' PATH never has it (a runtime installed with it would land in the release).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: station-bundle.sh DIR [PLATFORM]}
platform=${2:-}
NODE_VERSION=24.15.0
# Written afresh here, so a release never carries what an older build left in dist/admin (its page), nor an old key.
node "$root/scripts/posthog-key.ts" >&2
if [ "${STILLFAIL_STATION:-}" = ts ]; then
  native() { node "$root/scripts/native.ts" file "$1" "${platform:-darwin-arm64}"; }
  station="$(native launcher)"
  mesh="$(native mesh)"
  runner="$(native runner)"
  (cd "$root/station" && pnpm run build >&2)
  # Node for the platform, as nodejs.org builds it (checked against its SHASUMS256), kept between builds.
  node_dist="node-v$NODE_VERSION-${platform:-darwin-arm64}"
  cache="${STATION_TS_TARGET_DIR:-$HOME/Library/Caches/stillfail-build/station-ts}/node"
  mkdir -p "$cache"
  if [ ! -x "$cache/$node_dist/bin/node" ]; then
    curl -fsSL --retry 5 --retry-all-errors "https://nodejs.org/dist/v$NODE_VERSION/$node_dist.tar.gz" -o "$cache/$node_dist.tar.gz"
    curl -fsSL --retry 5 --retry-all-errors "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt" -o "$cache/SHASUMS256-$NODE_VERSION.txt"
    want=$(grep " $node_dist.tar.gz\$" "$cache/SHASUMS256-$NODE_VERSION.txt" | cut -d' ' -f1)
    got=$(shasum -a 256 "$cache/$node_dist.tar.gz" | cut -d' ' -f1)
    [ -n "$want" ] && [ "$want" = "$got" ] || { echo "$node_dist.tar.gz: checksum does not match" >&2; exit 1; }
    tar -xzf "$cache/$node_dist.tar.gz" -C "$cache"
  fi
else
case "$platform" in
  ""|darwin-arm64) station="${STILLFAIL_STATION_RS:-$root/mesh/target/release/stillfail-station}" ;;
  linux-x64|linux-arm64) station="$("$root/scripts/linux-station.sh" "$platform")" ;;
  *) echo "no such platform: $platform" >&2; exit 1 ;;
esac
fi
[ -x "$station" ] || { echo "stillfail-station is missing: cargo build --release in mesh/" >&2; exit 1; }
app="$out/stillfail"
rm -rf "$app"
mkdir -p "$app/bin" "$app/mesh/target/release" "$app/dist"
cp "$root/bin/stillfail" "$app/bin/"
ln -s stillfail "$app/bin/ember"
cp -R "$root/dist/admin" "$app/dist/admin"
cp "$station" "$app/mesh/target/release/stillfail-station"
ln -s stillfail-station "$app/mesh/target/release/ember-station"
if [ "${STILLFAIL_STATION:-}" = ts ]; then
  mkdir -p "$app/station/read" "$app/node/bin"
  cp "$root/station/dist/main.js" "$app/station/"
  cp "$root/station/dist/read/worker.js" "$app/station/read/"
  cp -R "$root/station/dist/skills" "$app/station/skills"
  cp "$mesh" "$runner" "$app/station/"
  cp "$cache/$node_dist/bin/node" "$app/node/bin/node"
fi
git -C "$root" rev-parse HEAD > "$app/VERSION"
git -C "$root" rev-list --count HEAD > "$app/BUILD"
