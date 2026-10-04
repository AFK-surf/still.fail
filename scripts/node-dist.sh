#!/bin/sh
# The Node a station runs on (.node-version's), for PLATFORM, as the releases keep it apart from the station's own
# (cloud/src/install.ts gets it once per version, when the machine lacks it): DIR/node/node-v<version>-<platform>.tar.gz
# (bin/node and its LICENSE, as nodejs.org builds them, checked against its SHASUMS256) and its .sha256.
#   node-dist.sh DIR [darwin-arm64|linux-x64|linux-arm64]   prints the tarball's path
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: node-dist.sh DIR [PLATFORM]}
platform=${2:-darwin-arm64}
version=$(cat "$root/.node-version")
dist="node-v$version-$platform"
cache="${STATION_TS_TARGET_DIR:-$HOME/Library/Caches/stillfail-build/station-ts}/node"
mkdir -p "$cache" "$out/node"
if [ ! -x "$cache/$dist/bin/node" ]; then
  curl -fsSL --retry 5 --retry-all-errors "https://nodejs.org/dist/v$version/$dist.tar.gz" -o "$cache/$dist.tar.gz"
  curl -fsSL --retry 5 --retry-all-errors "https://nodejs.org/dist/v$version/SHASUMS256.txt" -o "$cache/SHASUMS256-$version.txt"
  want=$(grep " $dist.tar.gz\$" "$cache/SHASUMS256-$version.txt" | cut -d' ' -f1)
  got=$(shasum -a 256 "$cache/$dist.tar.gz" | cut -d' ' -f1)
  [ -n "$want" ] && [ "$want" = "$got" ] || { echo "$dist.tar.gz: checksum does not match" >&2; exit 1; }
  tar -xzf "$cache/$dist.tar.gz" -C "$cache"
fi
file="$out/node/$dist.tar.gz"
tar -czf "$file" -C "$cache/$dist" bin/node LICENSE
shasum -a 256 "$file" | cut -d' ' -f1 > "$file.sha256"
echo "$file"
