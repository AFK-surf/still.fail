#!/bin/bash
set -eu
root=$(cd "$(dirname "$0")" && pwd)
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$root/target/tests}
case "${1:-test}" in
  prepare)
    cargo fetch --manifest-path "$root/Cargo.toml" --locked
    upstream=$(cargo metadata --manifest-path "$root/Cargo.toml" --locked --format-version 1 | jq -r '.packages[] | select(.name == "resvg") | .manifest_path')
    cargo fetch --manifest-path "$upstream" --locked
    exit ;;
  test) ;;
  *) echo 'test.sh [prepare|test]' >&2; exit 2 ;;
esac
upstream=$(cargo metadata --manifest-path "$root/Cargo.toml" --locked --offline --format-version 1 | jq -r '.packages[] | select(.name == "resvg") | .manifest_path')
cargo test --manifest-path "$upstream" --locked --offline --release -p resvg --test integration -- --test-threads=2
cargo test --manifest-path "$root/Cargo.toml" --locked --offline --release
cargo build --manifest-path "$root/Cargo.toml" --locked --offline --release --lib
export MOON_CC="$root/test-cc.sh" SVG_TEST_LIB="$CARGO_TARGET_DIR/release/libmbui_svg.a"
cd "$root/../.."
moon test --target native --release -p mbui/svgrender -p mbui/media
