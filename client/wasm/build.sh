#!/bin/sh
# Builds the web core into web/src/core/pkg (not committed), which
# web/src/core/worker.ts imports. Needs a clang that targets wasm32 for ring:
# Homebrew's llvm on macOS.
set -eu
# rustup's toolchain (with the wasm32 target), ahead of any Homebrew rust.
export PATH="$HOME/.cargo/bin:$PATH"
cd "$(dirname "$0")/.."
llvm=${LLVM_BIN:-/opt/homebrew/opt/llvm@22/bin}
CC_wasm32_unknown_unknown="$llvm/clang" AR_wasm32_unknown_unknown="$llvm/llvm-ar" \
  RUSTFLAGS='--cfg getrandom_backend="wasm_js"' \
  cargo build -p ember-core-wasm --profile wasm-release --target wasm32-unknown-unknown
target=${CARGO_TARGET_DIR:-target}
out=../web/src/core/pkg
rm -rf "$out"
wasm-bindgen --target web --out-dir "$out" "$target/wasm32-unknown-unknown/wasm-release/ember_core_wasm.wasm"
# When this core was built: a page on a newer one starts its own worker, and the older retires (web/src/core/built.ts).
printf 'export const BUILT_AT = %s000;\n' "$(date +%s)" > "$out/built.js"
printf 'export declare const BUILT_AT: number;\n' > "$out/built.d.ts"
ls -la "$out"
