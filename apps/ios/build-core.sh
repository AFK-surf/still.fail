#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Build the native IO shell in main's Rust workspace.
cd "$ROOT/client"
export RUSTUP_HOME="$ROOT/.airbuild/rust"
export RUSTUP_TOOLCHAIN="1.95.0"
export CARGO_HOME="$ROOT/.airbuild/cargo"
export CARGO_TARGET_DIR="$ROOT/.airbuild/cargo-target"
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-26.0}"
export PATH="$CARGO_HOME/bin:$RUSTUP_HOME/bin:$PATH:/opt/homebrew/bin"
CARGO="$CARGO_HOME/bin/cargo"
if [[ ! -x "$CARGO" ]]; then CARGO="$RUSTUP_HOME/bin/cargo"; fi
if [[ ! -x "$CARGO" ]]; then echo "Project-local Rust toolchain is required" >&2; exit 1; fi
GENERATED="$ROOT/.airbuild/generated/core"
mkdir -p "$GENERATED"
if [[ "${AIRBUILD_SIGN:-0}" == "1" || "${PLATFORM_NAME:-}" == "iphoneos" ]]; then
  TARGET="aarch64-apple-ios"
else
  TARGET="aarch64-apple-ios-sim"
fi
# Shared TypeScript logic runs in the system JavaScriptCore; Rust only supplies IO.
if ! command -v node >/dev/null || ! command -v pnpm >/dev/null; then
  echo "Node.js 24+ and pnpm are required to bundle the TypeScript core" >&2; exit 1
fi
pnpm --dir "$ROOT/client/core-ts" install --frozen-lockfile --prefer-offline
node "$ROOT/client/core-ts/scripts/ios-bundle.ts" "$GENERATED/stillfail-core.js"
"$CARGO" build --manifest-path "$ROOT/client/Cargo.toml" --locked -p stillfail-shell --lib --release --target "$TARGET"
cp "$CARGO_TARGET_DIR/$TARGET/release/libstillfail_shell.a" "$GENERATED/libstillfail_shell.a"
printf '%s\n' "$TARGET" > "$GENERATED/rust-target.txt"
