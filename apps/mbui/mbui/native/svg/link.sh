#!/bin/bash
# Keep MoonBit's memory first: the native shell uses that export for its calls.
set -eu
root=$(cd "$(dirname "$0")" && pwd)
input=${1:?input Wasm}
output=${2:?output Wasm}
cache=$root/target/link
mkdir -p "$cache"
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) host=arm64-macos; sha=ad66da82ac13f163e424b1643f16c6dfcccc98b5966296b43e52d3cab04f84a8 ;;
  Darwin-x86_64) host=x86_64-macos; sha=13a9b90be775c6389ce3d1f879cb8627bea56708ba8c122983941d53a8199b95 ;;
  Linux-aarch64) host=aarch64-linux; sha=89c07ea56faf38d0fbecf36ca8ec0721756716185f265b568e133d427f299bf8 ;;
  Linux-x86_64) host=x86_64-linux; sha=2dc9c7813f5375db93d96ead4b78222fcc3e2677bbb832297af4797782a37489 ;;
  MINGW*-aarch64|MSYS*-aarch64) host=arm64-windows; sha=492a8e1847a0be1554bb9a7f384227981d60bc013aedc02d8ba1372c3943178c ;;
  MINGW*-x86_64|MSYS*-x86_64) host=x86_64-windows; sha=17a2cbeac6b5693c5fbafab3838d3c65fd9c1eb38b05f5baec6c657e8c84995b ;;
  *) echo "SVG linker: unsupported host $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
bin=$cache/$host/binaryen-version_133/bin/wasm-merge
if [ ! -x "$bin" ]; then
  stage=$(mktemp -d "$cache/download.XXXXXX")
  trap 'rm -rf "$stage"' EXIT
  curl -fsSL -o "$stage/binaryen.tar.gz" "https://github.com/WebAssembly/binaryen/releases/download/version_133/binaryen-version_133-$host.tar.gz"
  [ "$(shasum -a 256 "$stage/binaryen.tar.gz" | awk '{print $1}')" = "$sha" ] || { echo 'SVG linker checksum mismatch' >&2; exit 1; }
  tar -xzf "$stage/binaryen.tar.gz" -C "$stage"
  mkdir -p "$cache/$host"
  mv "$stage/binaryen-version_133" "$cache/$host/"
  rm -rf "$stage"
  trap - EXIT
fi
bash "$root/build.sh" wasm "$cache/renderer.wasm"
mkdir -p "$(dirname "$output")"
linked=$(mktemp "$(dirname "$output")/.svg-link.XXXXXX")
trap 'rm -f "$linked"' EXIT
"$bin" "$input" moon "$cache/renderer.wasm" mbui_svg --rename-export-conflicts \
  --enable-simd --enable-multimemory --enable-gc --enable-reference-types --enable-multivalue \
  --enable-bulk-memory --enable-sign-ext --enable-nontrapping-float-to-int \
  --enable-mutable-globals --enable-exception-handling -o "$linked"
# Merging introduces temporaries; the app's initializer would exceed Wasmtime's local limit.
"${bin%wasm-merge}wasm-opt" "$linked" --simplify-locals-nostructure --vacuum --reorder-locals \
  --enable-simd --enable-multimemory --enable-gc --enable-reference-types --enable-multivalue \
  --enable-bulk-memory --enable-sign-ext --enable-nontrapping-float-to-int \
  --enable-mutable-globals --enable-exception-handling -o "$output"
