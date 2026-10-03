#!/bin/sh
# Builds the TypeScript station's native parts (station/native, docs/station-ts-native.md) for PLATFORM, from here (a
# Mac): the launcher (stillfail-station), the runner (stillfail-runner) and the mesh addon (mesh.node). Linux ones with
# cargo-zigbuild, for glibc 2.28 and later, as scripts/linux-station.sh builds the Rust station. Prints the directory
# they are in.
#   station-ts-native.sh darwin-arm64|linux-x64|linux-arm64
# Linux needs: brew install zig; cargo install --locked cargo-zigbuild; rustup target add x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
platform=${1:?usage: station-ts-native.sh darwin-arm64|linux-x64|linux-arm64}
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
cache=${STATION_TS_TARGET_DIR:-$HOME/Library/Caches/stillfail-build/station-ts}
out="$cache/out/$platform"
mkdir -p "$out"
build() { # build <crate dir> <artifact name> <name in out>
  case "$platform" in
    darwin-arm64)
      (cd "$root/station/native/$1" && CARGO_TARGET_DIR="$cache/darwin" cargo build --release >&2)
      cp "$cache/darwin/release/$2" "$out/$3" ;;
    linux-x64|linux-arm64)
      triple=$([ "$platform" = linux-x64 ] && echo x86_64-unknown-linux-gnu || echo aarch64-unknown-linux-gnu)
      (cd "$root/station/native/$1" && CARGO_TARGET_DIR="$cache/linux" cargo zigbuild --release --target "$triple.2.28" >&2)
      cp "$cache/linux/$triple/release/$2" "$out/$3" ;;
    *) echo "no such platform: $platform" >&2; exit 1 ;;
  esac
}
build launcher stillfail-station stillfail-station
build runner stillfail-runner stillfail-runner
case "$platform" in
  darwin-arm64) build mesh libstillfail_mesh.dylib mesh.node ;;
  *) build mesh libstillfail_mesh.so mesh.node ;;
esac
echo "$out"
