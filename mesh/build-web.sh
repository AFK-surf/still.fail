#!/bin/sh
# Builds the browser client into web/src/mesh/pkg (not committed). Needs a
# clang that targets wasm32 for ring: Homebrew's llvm on macOS.
set -eu
# rustup's toolchain (with the wasm32 target), ahead of any Homebrew rust.
export PATH="$HOME/.cargo/bin:$PATH"
cd "$(dirname "$0")/web"
llvm=${LLVM_BIN:-/opt/homebrew/opt/llvm@22/bin}
CC_wasm32_unknown_unknown="$llvm/clang" AR_wasm32_unknown_unknown="$llvm/llvm-ar" \
  RUSTFLAGS='--cfg getrandom_backend="wasm_js"' \
  cargo build --release --target wasm32-unknown-unknown
out=../../web/src/mesh/pkg
rm -rf "$out"
wasm-bindgen --target web --out-dir "$out" target/wasm32-unknown-unknown/release/ember_mesh_web.wasm
ls -la "$out"
