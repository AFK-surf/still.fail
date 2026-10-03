#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# UniFFI invokes cargo metadata in the current directory, even with --library.
cd "$ROOT/client"
export RUSTUP_HOME="$ROOT/.airbuild/rust"
export RUSTUP_TOOLCHAIN="1.95.0"
export CARGO_HOME="$ROOT/.airbuild/cargo"
export CARGO_TARGET_DIR="$ROOT/.airbuild/cargo-target"
export PATH="$CARGO_HOME/bin:$RUSTUP_HOME/bin:/opt/homebrew/bin:$PATH"
CARGO="$CARGO_HOME/bin/cargo"
if [[ ! -x "$CARGO" ]]; then CARGO="$RUSTUP_HOME/bin/cargo"; fi
if [[ ! -x "$CARGO" ]]; then echo "Project-local Rust toolchain is required" >&2; exit 1; fi
GENERATED="$ROOT/.airbuild/generated/core"
mkdir -p "$GENERATED"
HOST="$("$CARGO" -vV | sed -n 's/^host: //p')"
if [[ "${AIRBUILD_SIGN:-0}" == "1" || "${PLATFORM_NAME:-}" == "iphoneos" ]]; then
  TARGET="aarch64-apple-ios"
else
  TARGET="aarch64-apple-ios-sim"
fi
# Bindgen is the workspace's exactly pinned UniFFI 0.31.0 CLI, not a global tool.
"$CARGO" build --manifest-path "$ROOT/client/Cargo.toml" --locked -p stillfail-core-ffi --features bindgen --release --target "$HOST"
"$CARGO_TARGET_DIR/$HOST/release/uniffi-bindgen" generate --library "$CARGO_TARGET_DIR/$HOST/release/libstillfail_core_ffi.dylib" --language swift --config "$ROOT/client/ffi/uniffi.toml" --out-dir "$GENERATED"
# Clang discovers module.modulemap through Swift/header search paths.
cp "$GENERATED/StillFailCoreFFI.modulemap" "$GENERATED/module.modulemap"
"$CARGO" build --manifest-path "$ROOT/client/Cargo.toml" --locked -p stillfail-core-ffi --lib --release --target "$TARGET"
cp "$CARGO_TARGET_DIR/$TARGET/release/libstillfail_core_ffi.a" "$GENERATED/libstillfail_core_ffi.a"
printf '%s\n' "$TARGET" > "$GENERATED/rust-target.txt"
