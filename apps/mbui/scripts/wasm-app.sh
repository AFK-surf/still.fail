#!/bin/bash
# still.fail's Mac app in development, in Wasm (the user, 2026-11-03: no C of the app compiled): the app built for
# classic Wasm, run by mbui's native shell (mbui/src/host/wasm_shell.c) linked with the Mac host and the core's engine
# as the native app links them. The shell is compiled again only when what it is made of changes (the host's C, the
# calls tools/wasmhost writes of the declarations, the core's parts, wasmtime), never for a change of the app.
#
#   [APP=stillfail|sffilm] scripts/wasm-app.sh build | run [ENV…] | check
#     build: out/wasm-app/$APP, the app as one program (as e2e/run.sh's E2E_EXE); APP=sffilm: the media scenes'
#       program (media.sh preview's window)
#     check: the Wasm side of the native calls (x_wasm.mbt beside each x_native.mbt) as their declarations make it
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
H=mbui/src/host
# The files whose `extern "C"` calls the shell answers: mbui's host, the core's engine, the app's own.
decls="$H/host_native.mbt $H/device_native.mbt $H/stream_native.mbt $H/textref_native.mbt $H/native_native.mbt
  src/core/native.mbt src/stillfail/link_native.mbt src/pinyin/load_native.mbt src/sfreplay/emit_native.mbt
  src/sfreplay/trace_native.mbt"
O=$A/out/wasm-app
mkdir -p "$O"
case "${1:-build}" in
  check)
    exec "$MBUI_DIR/scripts/wasmhost" check "$O/thunks.c" $decls ;;
  build|run) ;;
  *) echo 'wasm-app.sh build | run [ENV…] | check' >&2; exit 2 ;;
esac
"$MBUI_DIR/scripts/wasmhost" gen "$O/thunks.c" $decls > /dev/null
APP=${APP:-stillfail}
t0=$SECONDS
log=$O/moon.log
if ! moon build --target wasm --release src/$APP > "$log" 2>&1; then
  awk '/^Error/ { n=9 } n>0 { print substr($0,1,300); n-- }' "$log" >&2
  exit 1
fi
echo "wasm-app: the app in $((SECONDS - t0)) s"
# wasmtime's C API, a release of its own (Apache-2.0), fetched once by its checksum
WT_VERSION=50.0.1
WT_SHA=a49327ca596fae51cd92e230265132112bb7896c5a24e4d58cd05b56612e26bb
WT=$A/out/wasmtime-v$WT_VERSION-aarch64-macos-c-api
if [ ! -f "$WT/lib/libwasmtime.dylib" ]; then
  tar_file=$A/out/wasmtime-v$WT_VERSION.tar.xz
  curl -fsSL --retry 3 -o "$tar_file" \
    "https://github.com/bytecodealliance/wasmtime/releases/download/v$WT_VERSION/wasmtime-v$WT_VERSION-aarch64-macos-c-api.tar.xz"
  [ "$(shasum -a 256 "$tar_file" | awk '{print $1}')" = "$WT_SHA" ] || { echo 'wasm-app: wasmtime: not the release asked for' >&2; exit 1; }
  tar xf "$tar_file" -C "$A/out"
  rm -f "$tar_file"
fi
# the core's native parts, as the native app has them
bash "$D/core.sh" apple-native aarch64-apple-darwin > "$O/core.log" 2>&1 || { cat "$O/core.log"; exit 1; }
moon_root=${MOON_HOME:-$(dirname "$(dirname "$(command -v moon)")")}
host_c=$(ls $H/apple_*.m $H/mac_app.m)
stubs="src/core/core_native.c src/pinyin/read_file.c src/sfreplay/trace_files.c src/stillfail/core_engine.m"
shell_src=$(cat $host_c $H/*.h $H/wasm_shell.c "$O/thunks.c" $stubs "$moon_root/lib/runtime/runtime.c" "$moon_root/include/moonbit.h" \
  out/core/aarch64-apple-darwin/*.a "$WT/lib/libwasmtime.dylib" "$0" | cksum)
if [ ! -x "$O/shell" ] || [ "$(cat "$O/shell.src" 2>/dev/null)" != "$shell_src" ]; then
  t0=$SECONDS
  # (each source its own object, side by side)
  mkdir -p "$O/obj"
  pids=()
  for f in $host_c $H/wasm_shell.c "$O/thunks.c" $stubs "$moon_root/lib/runtime/runtime.c"; do
    obj=$O/obj/$(echo "$f" | tr '/' '_').o
    flags="-O2 -I$moon_root/include -I$WT/include -I$H"
    case "$f" in *.m) flags="$flags -fobjc-arc -fblocks" ;; esac
    clang $flags -c "$f" -o "$obj" &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p"; done
  # (wasmtime's dynamic library: its static one carries Rust's std, as the core's shell does, twice in one link)
  clang -o "$O/shell" "$O"/obj/*.o "$WT/lib/libwasmtime.dylib" -Wl,-rpath,"$WT/lib" \
    -framework Cocoa -framework Metal -framework QuartzCore -framework CoreText -framework CoreGraphics \
    -framework ImageIO -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework WebKit \
    -framework AuthenticationServices -framework SystemConfiguration -framework Security -framework LocalAuthentication \
    -framework CoreFoundation -framework Foundation -liconv \
    out/core/aarch64-apple-darwin/libmbui_core.a out/core/aarch64-apple-darwin/libstillfail_shell.a \
    -Fout/core/hermes/Library/Frameworks/macosx -framework hermes -lc++ \
    -Wl,-rpath,"$A/out/core/hermes/Library/Frameworks/macosx"
  echo "$shell_src" > "$O/shell.src"
  echo "wasm-app: the shell in $((SECONDS - t0)) s"
fi
program=$A/$(pkg_build $APP wasm release)/$APP.wasm
# (the app as one program, for what runs the native one by its path: e2e/run.sh's E2E_EXE)
printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$O/shell" "$program" > "$O/$APP"
chmod +x "$O/$APP"
if [ "${1:-build}" = run ]; then
  shift
  export MB_CORE_BUNDLE=${MB_CORE_BUNDLE:-$A/out/core/core.hbc}
  [ -f "$MB_CORE_BUNDLE" ] || bash "$D/core.sh" hermes apple > "$O/hermes.log" 2>&1
  for kv in "$@"; do export "$kv"; done
  on_screen "$O/shell" "$program"
fi
