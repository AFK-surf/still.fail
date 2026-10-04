#!/bin/sh
# The Node the station runs on (.node-version), on this machine: ~/.local/node-v<version>-<platform>, got from
# nodejs.org once (checked against its SHASUMS256) when it is not there. Prints its bin directory, for PATH: what the
# Macs that build and check (mini1's runners: .github/actions/setup-mac; studio) run what they run on.
#   node-here.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
version=$(cat "$root/.node-version")
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) platform=darwin-arm64 ;;
  Linux-x86_64) platform=linux-x64 ;;
  Linux-aarch64|Linux-arm64) platform=linux-arm64 ;;
  *) echo "no Node build for $(uname -s) $(uname -m)" >&2; exit 1 ;;
esac
dist="node-v$version-$platform"
home="$HOME/.local/$dist"
if [ ! -x "$home/bin/node" ]; then
  mkdir -p "$HOME/.local"
  tmp=$(mktemp -d "$HOME/.local/.node.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --retry 5 --retry-all-errors "https://nodejs.org/dist/v$version/$dist.tar.gz" -o "$tmp/$dist.tar.gz"
  want=$(curl -fsSL --retry 5 --retry-all-errors "https://nodejs.org/dist/v$version/SHASUMS256.txt" | grep " $dist.tar.gz\$" | cut -d' ' -f1)
  got=$({ shasum -a 256 "$tmp/$dist.tar.gz" 2>/dev/null || sha256sum "$tmp/$dist.tar.gz"; } | cut -d' ' -f1)
  [ -n "$want" ] && [ "$want" = "$got" ] || { echo "$dist.tar.gz: checksum does not match" >&2; exit 1; }
  tar -xzf "$tmp/$dist.tar.gz" -C "$tmp"
  # Another runner may have put it there meanwhile: the first one stays.
  mv "$tmp/$dist" "$home" 2>/dev/null || true
fi
echo "$home/bin"
