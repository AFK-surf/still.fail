#!/bin/sh
# Node's own Linux build, of the version run here, for a station release (scripts/station-bundle.sh): downloaded once
# into the build cache, checked against nodejs.org's SHASUMS256. Prints the path of its bin/node.
#   linux-node.sh linux-x64|linux-arm64
set -eu
case "${1:?usage: linux-node.sh linux-x64|linux-arm64}" in
  linux-x64) arch=x64 ;;
  linux-arm64) arch=arm64 ;;
  *) echo "no such platform: $1" >&2; exit 1 ;;
esac
version=$(node -v)
name="node-$version-linux-$arch"
cache=${NODE_CACHE:-$HOME/Library/Caches/ember-build/node}
if [ ! -x "$cache/$name/bin/node" ]; then
  mkdir -p "$cache"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "https://nodejs.org/dist/$version/$name.tar.xz" -o "$tmp/$name.tar.xz"
  curl -fsSL "https://nodejs.org/dist/$version/SHASUMS256.txt" -o "$tmp/SHASUMS256.txt"
  (cd "$tmp" && grep " $name.tar.xz\$" SHASUMS256.txt | shasum -a 256 -c - >&2)
  tar -xJf "$tmp/$name.tar.xz" -C "$tmp"
  rm -rf "${cache:?}/$name"
  mv "$tmp/$name" "$cache/$name"
fi
echo "$cache/$name/bin/node"
