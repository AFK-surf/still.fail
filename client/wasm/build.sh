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
# Smaller again with binaryen's wasm-opt (4.7 MB to 3.2 MB with opt-level z): what the browser downloads and compiles.
opt=$(command -v wasm-opt || echo /opt/homebrew/bin/wasm-opt)
if [ -x "$opt" ]; then
  "$opt" -Oz --enable-bulk-memory --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals \
    --enable-reference-types --enable-multivalue "$out/ember_core_wasm_bg.wasm" -o "$out/ember_core_wasm_bg.wasm"
else
  echo "note: no wasm-opt (brew install binaryen): the web core is left larger" >&2
fi
# When this core was built: a page on a newer one starts its own worker, and the older retires (web/src/core/built.ts).
printf 'export const BUILT_AT = %s000;\n' "$(date +%s)" > "$out/built.js"
printf 'export declare const BUILT_AT: number;\n' > "$out/built.d.ts"
ls -la "$out"
