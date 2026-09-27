#!/bin/sh
# Builds ember-station for Linux from here (a Mac): cargo-zigbuild, with zig as the C compiler and linker, for glibc
# 2.28 and later (Debian 10, Ubuntu 20.04, RHEL 8 on). Prints the binary's path.
#   linux-station.sh linux-x64|linux-arm64
# Needs: brew install zig; cargo install --locked cargo-zigbuild; rustup target add x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
case "${1:?usage: linux-station.sh linux-x64|linux-arm64}" in
  linux-x64) triple=x86_64-unknown-linux-gnu ;;
  linux-arm64) triple=aarch64-unknown-linux-gnu ;;
  *) echo "no such platform: $1" >&2; exit 1 ;;
esac
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
target=${LINUX_TARGET_DIR:-$HOME/Library/Caches/ember-build/linux}
(cd "$root/mesh" && CARGO_TARGET_DIR="$target" cargo zigbuild --release --target "$triple.2.28" >&2)
echo "$target/$triple/release/ember-station"
