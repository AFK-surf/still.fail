#!/bin/bash
set -eu
root=$(cd "$(dirname "$0")" && pwd)
kind=${1:?native or wasm}
out=${2:?output file}
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$root/target}
case "$kind" in
  wasm)
    rustup target add wasm32-unknown-unknown
    export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
    export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C target-feature=+simd128"
    cargo build --manifest-path "$root/Cargo.toml" --locked --release --lib --target wasm32-unknown-unknown
    artifact=$CARGO_TARGET_DIR/wasm32-unknown-unknown/release/mbui_svg.wasm
    ;;
  native)
    cargo build --manifest-path "$root/Cargo.toml" --locked --release --lib
    artifact=$CARGO_TARGET_DIR/release/libmbui_svg.a
    ;;
  *) echo "unknown SVG target: $kind" >&2; exit 2 ;;
esac
mkdir -p "$(dirname "$out")"
cp "$artifact" "$out"
