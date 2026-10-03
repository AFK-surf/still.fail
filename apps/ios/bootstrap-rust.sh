#!/bin/bash
# Keep every Rust tool/target/cache inside this Project. Never edit shell profiles.
set -e -o pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export RUSTUP_HOME="$ROOT/.airbuild/rust"
export CARGO_HOME="$ROOT/.airbuild/cargo"
export RUSTUP_TOOLCHAIN=1.95.0
export RUSTUP_INIT_SKIP_PATH_CHECK=yes
export RUSTUP_TERM_PROGRESS_WHEN=never
export PATH="$CARGO_HOME/bin:/opt/homebrew/bin:$PATH"
if [ "${AIRBUILD_SIGN:-0}" = 1 ] || [ "${PLATFORM_NAME:-}" = iphoneos ]; then
  TARGET=aarch64-apple-ios
else
  TARGET=aarch64-apple-ios-sim
fi
mkdir -p "$ROOT/.airbuild/tools"
if [ ! -x "$CARGO_HOME/bin/rustup" ]; then
  case "$(uname -m)" in
    arm64) HOST=aarch64-apple-darwin ;;
    x86_64) HOST=x86_64-apple-darwin ;;
    *) printf 'Unsupported Mac architecture\n' >&2; exit 1 ;;
  esac
  /usr/bin/curl --fail --location --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 120 --retry 2 \
    "https://static.rust-lang.org/rustup/dist/$HOST/rustup-init" \
    -o "$ROOT/.airbuild/tools/rustup-init"
  chmod u+x "$ROOT/.airbuild/tools/rustup-init"
  "$ROOT/.airbuild/tools/rustup-init" -y --no-modify-path --profile minimal \
    --default-toolchain "$RUSTUP_TOOLCHAIN" --default-host "$HOST" \
    --target "$TARGET"
fi
if ! "$CARGO_HOME/bin/rustup" run "$RUSTUP_TOOLCHAIN" rustc --version >/dev/null 2>&1; then
  "$CARGO_HOME/bin/rustup" toolchain install "$RUSTUP_TOOLCHAIN" --profile minimal
fi
"$CARGO_HOME/bin/rustup" target add "$TARGET" --toolchain "$RUSTUP_TOOLCHAIN"
"$CARGO_HOME/bin/cargo" --version
