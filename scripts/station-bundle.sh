#!/bin/sh
# Lays out the still.fail station's release in DIR/stillfail for PLATFORM (default darwin-arm64): the station in
# TypeScript (station/, docs/station-ts.md) with the Node it runs on and its native parts, prebuilt (scripts/native.ts:
# launcher, mesh, runner). scripts/release.sh packs it for install.sh; the desktop app (apps/desktop/build.sh) carries
# it and runs it itself. The layout:
#   stillfail/bin/stillfail                               (the command people and services run; bin/ember beside it)
#   stillfail/mesh/target/release/stillfail-station       (the launcher, with the Rust station's command line and path,
#                                                          ember-station beside it: what the installer, bin/stillfail,
#                                                          the desktop app and services written by older releases run)
#   stillfail/station/{main.js, read/worker.js, skills/, mesh.node, stillfail-runner, package.json}
#   stillfail/node/bin/node                               (the Node it runs on, NODE_VERSION's)
#   stillfail/dist/admin/posthog.json                     (only the PostHog key the station reports errors with, when
#                                                          $STILLFAIL_POSTHOG names one: scripts/posthog-key.ts; the
#                                                          station finds its release as dist/admin's parent's parent)
#   stillfail/VERSION, BUILD                              (the commit; the commits in its history: version 0.1.<BUILD>)
# The Node is the release's own: the agents' PATH never has it (a runtime installed with it would land in the release).
#   station-bundle.sh DIR [darwin-arm64|linux-x64|linux-arm64]
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: station-bundle.sh DIR [PLATFORM]}
platform=${2:-darwin-arm64}
case "$platform" in
  darwin-arm64|linux-x64|linux-arm64) ;;
  *) echo "no such platform: $platform" >&2; exit 1 ;;
esac
NODE_VERSION=24.15.0
# Written afresh here, so a release never carries what an older build left in dist/admin (its page), nor an old key.
node "$root/scripts/posthog-key.ts" >&2
native() { node "$root/scripts/native.ts" file "$1" "$platform"; }
launcher="$(native launcher)"
mesh="$(native mesh)"
runner="$(native runner)"
(cd "$root/station" && pnpm run build >&2)
# Node for the platform, as nodejs.org builds it (checked against its SHASUMS256), kept between builds.
node_dist="node-v$NODE_VERSION-$platform"
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
app="$out/stillfail"
rm -rf "$app"
mkdir -p "$app/bin" "$app/mesh/target/release" "$app/dist" "$app/station/read" "$app/node/bin"
cp "$root/bin/stillfail" "$app/bin/"
ln -s stillfail "$app/bin/ember"
cp -R "$root/dist/admin" "$app/dist/admin"
cp "$launcher" "$app/mesh/target/release/stillfail-station"
ln -s stillfail-station "$app/mesh/target/release/ember-station"
cp "$root/station/dist/main.js" "$app/station/"
cp "$root/station/dist/read/worker.js" "$app/station/read/"
cp -R "$root/station/dist/skills" "$app/station/skills"
cp "$mesh" "$runner" "$app/station/"
# The bundle is an ES module: said, so Node neither guesses nor takes the type of a package.json above the release
# (the desktop app built in apps/desktop has one: every command warned).
printf '{"type":"module"}\n' > "$app/station/package.json"
cp "$cache/$node_dist/bin/node" "$app/node/bin/node"
git -C "$root" rev-parse HEAD > "$app/VERSION"
git -C "$root" rev-list --count HEAD > "$app/BUILD"
