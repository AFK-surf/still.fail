#!/bin/bash
# Sourced by native host builds. The application's core already carries this library.
image_host_library() {
  local target=$1 out=$2 artifact
  if [ -n "${MBUI_IMAGE_ARCHIVE:-}" ]; then
    artifact=$MBUI_IMAGE_ARCHIVE
  else
    export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/native/svg/target}"
    rustup target add "$target"
    cargo build --manifest-path "$ROOT/native/svg/Cargo.toml" --locked --release --lib --target "$target"
    case "$target" in
      *windows*) artifact=$CARGO_TARGET_DIR/$target/release/mbui_svg.lib ;;
      *) artifact=$CARGO_TARGET_DIR/$target/release/libmbui_svg.a ;;
    esac
  fi
  mkdir -p "$(dirname "$out")"
  if ! cmp -s "$artifact" "$out"; then
    cp "$artifact" "$out"
    # moon watches source mtimes, mbc subsequently keys the link by archive content.
    touch "$ROOT/src/host/png.mbt"
  fi
  export MBC_LINK_ARCHIVE=$out
}
