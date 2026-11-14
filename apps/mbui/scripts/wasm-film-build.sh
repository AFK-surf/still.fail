#!/bin/bash
# Build the Wasm scene and its Mac offscreen host into a fresh native-part directory.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
[ "$#" -eq 1 ] || { echo 'wasm-film-build: OUT_DIR' >&2; exit 2; }
case "$1" in /*) out=$1 ;; *) out="$PWD/$1" ;; esac
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || {
  echo 'wasm-film-build: an Apple Silicon Mac is required' >&2; exit 2;
}
cd "$A"
mkdir -p "$out" out
log=$(mktemp "$A/out/wasm-build.XXXXXXXX")
trap 'rm -f "$log"' EXIT
if ! moon build --target wasm --release src/sfwasmfilm >"$log" 2>&1; then
  awk '/^Error/ { n=9 } n>0 { print substr($0,1,300); n-- }' "$log" >&2
  tail -n 20 "$log" | cut -c1-300 >&2
  exit 1
fi
tail -n 1 "$log" >&2
node_root=$(dirname "$(dirname "$(node -p 'process.execPath')")")
node_include=''
for candidate in "${NODE_INCLUDE:-}" "$node_root/include/node" /opt/homebrew/include/node /usr/local/include/node \
  "$HOME/.cache/node-gyp/$(node -p 'process.versions.node')/include/node"; do
  if [ -n "$candidate" ] && [ -f "$candidate/node_api.h" ]; then node_include=$candidate; break; fi
done
[ -n "$node_include" ] || { echo 'wasm-film-build: Node headers not found; set NODE_INCLUDE' >&2; exit 1; }
moon_root=${MOON_HOME:-$(dirname "$(dirname "$(command -v moon)")")}
# (the host compiled again only when its sources, the toolchain's header or Node's differ from what it was made of)
host_src=$(cat tools/wasm-film/native_host.m ../../libs/mbui/src/host/apple_*.m ../../libs/mbui/src/host/*.h "$moon_root/include/moonbit.h" \
  "$node_include/node_api.h" "$0" | cksum)
# (native.ts builds each renderer into a new directory: the host kept by its sources in this machine's cache too, so a
# change to the app's MoonBit alone compiles no C)
host_cache=${MBUI_FILM_HOST_CACHE:-${XDG_CACHE_HOME:-$HOME/Library/Caches}/stillfail-native/wasm-film-host}
host_kept=$host_cache/$(echo "$host_src" | shasum | cut -c1-40).node
if [ -f "$out/native.node" ] && [ "$(cat "$out/native.node.src" 2>/dev/null)" = "$host_src" ]; then :
elif [ -f "$host_kept" ]; then
  cp "$host_kept" "$out/native.node"
  echo "$host_src" > "$out/native.node.src"
else
clang -O2 -std=gnu11 -fobjc-arc -fblocks -bundle -undefined dynamic_lookup \
  -DNODE_GYP_MODULE_NAME=mbui_native -I"$node_include" -I"$moon_root/include" -I../../libs/mbui/src/host \
  tools/wasm-film/native_host.m ../../libs/mbui/src/host/apple_render.m \
  -framework Cocoa -framework CoreText -framework CoreGraphics -framework Metal -framework QuartzCore -framework ImageIO \
  -framework AVFoundation -framework CoreVideo -framework CoreMedia \
  -o "$out/native.node"
echo "$host_src" > "$out/native.node.src"
mkdir -p "$host_cache"
cp "$out/native.node" "$host_kept.$$" && mv -f "$host_kept.$$" "$host_kept"
fi
cp _build/wasm/release/build/stillfail/sfwasmfilm/sfwasmfilm.wasm "$out/scene.wasm"
cp tools/wasm-film/sffilm tools/wasm-film/run.mjs tools/wasm-film/compact.mjs scripts/media.sh "$out/"
chmod +x "$out/sffilm"
