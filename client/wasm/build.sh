#!/bin/sh
# Builds the web core into web/src/core/pkg (not committed), which
# web/src/core/worker.ts imports. Needs a clang that targets wasm32 for ring:
# LLVM from LLVM_BIN, Homebrew, or PATH.
set -eu
# rustup's toolchain (with the wasm32 target), ahead of any Homebrew rust.
export PATH="$HOME/.cargo/bin:$PATH"
cd "$(dirname "$0")/.."
llvm=${LLVM_BIN:-}
if [ -z "$llvm" ]; then
  # Keep the maintainer toolchain preferred, then support Intel Macs and unversioned LLVM.
  for candidate in /opt/homebrew/opt/llvm@22/bin /usr/local/opt/llvm@22/bin /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin; do
    if [ -x "$candidate/clang" ] && [ -x "$candidate/llvm-ar" ]; then llvm=$candidate; break; fi
  done
fi
if [ -n "$llvm" ]; then
  cc="$llvm/clang"
  ar="$llvm/llvm-ar"
else
  cc=$(command -v clang || true)
  ar=$(command -v llvm-ar || true)
fi
if [ ! -x "$cc" ] || [ ! -x "$ar" ]; then
  echo "Install LLVM with clang and llvm-ar, or set LLVM_BIN to its bin directory." >&2
  exit 1
fi
if ! "$cc" --print-targets | grep -q wasm32; then
  echo "$cc does not support wasm32; set LLVM_BIN to a WebAssembly-capable LLVM installation." >&2
  exit 1
fi
CC_wasm32_unknown_unknown="$cc" AR_wasm32_unknown_unknown="$ar" \
  RUSTFLAGS='--cfg getrandom_backend="wasm_js"' \
  cargo build --locked -p stillfail-core-wasm --profile wasm-release --target wasm32-unknown-unknown
target=${CARGO_TARGET_DIR:-target}
out=../web/src/core/pkg
rm -rf "$out"
wasm-bindgen --target web --out-dir "$out" "$target/wasm32-unknown-unknown/wasm-release/stillfail_core_wasm.wasm"
# When this core was built: a page on a newer one starts its own worker, and the older retires (web/src/core/built.ts).
printf 'export const BUILT_AT = %s000;\n' "$(date +%s)" > "$out/built.js"
printf 'export declare const BUILT_AT: number;\n' > "$out/built.d.ts"
ls -la "$out"
