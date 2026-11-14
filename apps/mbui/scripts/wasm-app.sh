#!/bin/bash
# still.fail's Mac app in development, in Wasm (the user, 2026-11-03: no C of the app compiled): the app built for
# classic Wasm, run by mbui's native shell (mbui/src/host/wasm_shell.c) linked with the Mac host and the core's engine
# as the native app links them. The shell is compiled again only when what it is made of changes (the host's C, the
# calls tools/wasmhost writes of the declarations, the core's parts, wasmtime), never for a change of the app.
#
#   [APP=stillfail|sffilm] [PLATFORM=mac|android|ios|windows] scripts/wasm-app.sh build | run [ENV…] | check
#     build: out/wasm-app/$APP, the app as one program (as e2e/run.sh's E2E_EXE); APP=sffilm: the media scenes'
#       program (media.sh preview's window)
#     PLATFORM=android: the shell an APK (scripts/android.sh's, its variables: ABI, EMU_PORT…), the app put beside
#       it on the emulator; run's argument the script MainActivity is started with
#     PLATFORM=ios: the shell an app (scripts/ios.sh's, its variables: MBUI_IOS_DEVICE…) run on the simulator, which
#       reads the app where it is here; run's argument the script, as ios.sh's
#     PLATFORM=windows: (Git Bash, MSVC) the shell a program of its own, out/wasm-app/windows/stillfail.exe, with the
#       DLLs and core.hbc beside it
#  check: the Wasm side of the native calls as their declarations make it
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
H=../../libs/mbui/src/host
# The files whose `extern "C"` calls the shell answers: mbui's host, the core's engine, the app's own.
decls="$H/host_native.mbt $H/device_native.mbt $H/stream_native.mbt $H/textref_native.mbt $H/native_native.mbt $H/terminal_native.mbt
  src/core/native.mbt src/stillfail/link_native.mbt src/sfreplay/emit_native.mbt
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
# (--no-strip: the program keeps its functions' names, so that a trap's stack says them: the Android shell's report,
# wasm_shell.c; without it the name section holds the module's name alone)
if ! moon build --target wasm --release --no-strip src/$APP > "$log" 2>&1; then
  awk '/^Error/ { n=9 } n>0 { print substr($0,1,300); n-- }' "$log" >&2
  exit 1
fi
echo "wasm-app: the app in $((SECONDS - t0)) s"
program=$A/$(pkg_build $APP wasm release)/$APP.wasm
# wasmtime's command line (its release for this machine, fetched once by its checksum), which compiles a program ahead
# for a device's shell: WT_CLI; WT_SAME, what makes its compilation the C API's default engine's (the command line's own
# collector is another: a program compiled without it the shell refuses)
WT_SAME="-C collector=drc"
wasmtime_cli() {
  local host sha
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) host=aarch64-macos sha=960e5216c7ebd7e9b45e6561d15821b8b801b7d54aee28c7b91921aeb30c65c8 ;;
    Linux-x86_64) host=x86_64-linux sha=685466455dd42a14774a86c36c8f2e45cbb9bd6d92a850139315df60a75498a5 ;;
    Linux-aarch64) host=aarch64-linux sha=d737e077416d78fbfb0a008229ec27d6a0fd5a4924874b8c38b293c850cf4094 ;;
    *) echo "wasm-app: no wasmtime command line for $(uname -s) $(uname -m)" >&2; exit 1 ;;
  esac
  WT_CLI=$A/out/wasmtime-v50.0.1-$host/wasmtime
  [ -x "$WT_CLI" ] && return 0
  curl -fsSL --retry 3 -o "$A/out/wasmtime-cli.tar.xz" \
    "https://github.com/bytecodealliance/wasmtime/releases/download/v50.0.1/wasmtime-v50.0.1-$host.tar.xz"
  [ "$(shasum -a 256 "$A/out/wasmtime-cli.tar.xz" | awk '{print $1}')" = $sha ] \
    || { echo 'wasm-app: wasmtime: not the release asked for' >&2; exit 1; }
  tar xf "$A/out/wasmtime-cli.tar.xz" -C "$A/out"
  rm -f "$A/out/wasmtime-cli.tar.xz"
}
if [ "${PLATFORM:-mac}" = android ]; then
  # Android's: the shell an APK of mbui's Android host, the app's C and wasmtime (scripts/android.sh built with
  # MBUI_WASM_THUNKS), installed only when it changed; the app compiled here for the device (wasmtime's command line) and put
  # in its files as app.cwasm, where the shell reads it
  t0=$SECONDS
  MBUI_WASM_THUNKS=$O/thunks.c MBUI_WASM_STUBS="$A/src/sfreplay/trace_files.c" bash "$D/android.sh" build > "$O/android.log" 2>&1 || { tail -40 "$O/android.log"; exit 1; }
  echo "wasm-app: the Android shell in $((SECONDS - t0)) s"
  # (compiled here for the device, as the shell's wasmtime would compile it there: Cranelift over 18 MB of Wasm on
  # the emulator took more memory than it had, the system's low-memory killer ending the app and others with it)
  wasmtime_cli
  case "${ABI:-arm64-v8a}" in x86_64) target=x86_64-linux-android ;; *) target=aarch64-linux-android ;; esac
  t0=$SECONDS
  # (how its traps are taken, MBUI_WASM_TRAPS: "signals", a phone's development build, as ever (a trap ends the process,
  # nothing said); "checked", in its code, each said with its stack (an emulator's, hunting a crash: its CPU +15% to
  # +62%, #4008). Said beside it, app.traps, for the shell to take the same: wasm_shell.c)
  traps=${MBUI_WASM_TRAPS:-signals}
  case $traps in
    signals) sbt=y ;;
    checked) sbt=n ;;
    *) echo "wasm-app: MBUI_WASM_TRAPS is signals or checked, not $traps" >&2; exit 2 ;;
  esac
  "$WT_CLI" compile $WT_SAME -O signals-based-traps=$sbt --target $target "$program" -o "$O/app-android.cwasm"
  printf '%s' "$traps" > "$O/app-android.traps"
  echo "wasm-app: compiled for $target in $((SECONDS - t0)) s"
  if [ "${1:-build}" = run ]; then
    shift
    apk_file=$A/android/app/build/outputs/apk/debug/app-debug.apk
    sum=$(shasum "$apk_file" | awk '{print $1}')
    if [ "$sum" != "$(cat "$O/android.installed" 2>/dev/null)" ]; then
      bash "$D/android.sh" install
      echo "$sum" > "$O/android.installed"
    fi
    bash "$D/android.sh" put "$O/app-android.traps" app.traps
    bash "$D/android.sh" put "$O/app-android.cwasm" app.cwasm
    INSTALL=0 bash "$D/android.sh" run "$@"
  fi
  exit 0
fi
if [ "${PLATFORM:-mac}" = windows ]; then
  # Windows' (Git Bash, MSVC's environment, as scripts/win.sh): the shell a program of mbui's Windows host, the app's C,
  # the core's engine and shell (their import libraries, scripts/native.ts's) and wasmtime (wasmtime.dll), compiled
  # with cl a source to an object, kept while it and the headers beside it are as they were; beside it the DLLs and core.hbc,
  # as the native app has them. Its run: out/wasm-app/windows/stillfail.exe PROGRAM.wasm.
  W=$O/windows
  mkdir -p "$W"
  WT_W=$A/out/wasmtime-v50.0.1-x86_64-windows-c-api
  if [ ! -f "$WT_W/lib/wasmtime.dll.lib" ]; then
    curl -fsSL --retry 3 -o "$A/out/wasmtime-win.zip" \
      "https://github.com/bytecodealliance/wasmtime/releases/download/v50.0.1/wasmtime-v50.0.1-x86_64-windows-c-api.zip"
    [ "$(sha256sum "$A/out/wasmtime-win.zip" | awk '{print $1}')" = 8b461d9dc12b076d0414b1023433bbb2dc08d3b1c0f0a156853ede35f0147802 ] \
      || { echo 'wasm-app: wasmtime: not the release asked for' >&2; exit 1; }
    (cd "$A/out" && unzip -q -o wasmtime-win.zip && rm -f wasmtime-win.zip)
  fi
  engine=$(cd "$SF_SRC" && node scripts/native.ts path engine win32-x64) || exit 1
  shell=$(cd "$SF_SRC" && node scripts/native.ts path shell win32-x64) || exit 1
  # WebView2's SDK (win_views.cpp), as mbui's win.sh fetches it
  WV2=$MBUI_DIR/out/webview2/1.0.4258.31
  if [ ! -f "$WV2/build/native/include/WebView2.h" ]; then
    mkdir -p "$MBUI_DIR/out/webview2"
    curl -sSfL --retry 3 -o "$WV2.nupkg" "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.4258.31"
    (cd "$(dirname "$WV2")" && unzip -q -o "$WV2.nupkg" -d "$WV2" && rm -f "$WV2.nupkg")
  fi
  HERMESC=$(cygpath -m "$engine/hermesc.exe") bash "$D/core.sh" hermes > "$O/hermes.log" 2>&1 \
    || { tail -20 "$O/hermes.log"; exit 1; }
  moon_root=$(cygpath -u "${MOON_HOME:-$(dirname "$(dirname "$(command -v moon)")")}")
  t0=$SECONDS
  win() { cygpath -w "$1"; }
  flags="-nologo -O2 -utf-8 -W0 -I$(win "$moon_root/include") -I$(win "$WT_W/include") -I$(win "$A/$H") -I$(win "$A/engine")
    -I$(win "$WV2/build/native/include") -I$(win "$A/src/host")"
  # (cl's own: -Fo the object, -c; C++ the host's .cpp, with exceptions as it is compiled natively)
  objs=()
  pids=()
  for f in $H/win_*.c $H/win_*.cpp $H/wasm_shell.c "$O/thunks.c" src/stillfail/win_engine.c src/core/core_native.c \
      src/sfreplay/trace_files.c "$moon_root/lib/runtime/runtime.c"; do
    o=$W/obj/$(echo "${f#"$A"/}" | tr '/\\:' '___').obj
    mkdir -p "$W/obj"
    objs+=("$o")
    extra=
    case "$f" in *.cpp) extra="-EHsc -std:c++20" ;; esac
    sum=$( (echo "$flags $extra"; cat "$f" $H/*.h src/host/*.h engine/*.h) | sha256sum | cut -c1-40)
    [ -f "$o" ] && [ "$(cat "$o.sum" 2>/dev/null)" = "$sum" ] && continue
    (rm -f "$o.sum"; cl.exe $flags $extra -c "$(win "$f")" -Fo"$(win "$o")" > "$o.log" 2>&1 && echo "$sum" > "$o.sum" ||
      { cat "$o.log" >&2; exit 1; }) &
    pids+=($!)
  done
  for p in ${pids[@]+"${pids[@]}"}; do wait "$p" || exit 1; done
  # (the engine's and the shell's import libraries named by the host's #pragma comment, found where LIB says, as
  # scripts/win.sh has it)
  export LIB="$(win "$engine");$(win "$shell");$LIB"
  # (MSVC's link, beside its cl: Git Bash's own /usr/bin/link is another program)
  "$(dirname "$(command -v cl.exe)")/link.exe" -nologo -out:"$(win "$W/stillfail.exe")" $(for o in "${objs[@]}"; do win "$o"; done) \
    "$(win "$WT_W/lib/wasmtime.dll.lib")" "$(win "$WV2/build/native/x64/WebView2LoaderStatic.lib")" > "$W/link.log" 2>&1 || { cat "$W/link.log"; exit 1; }
  cp "$WT_W/lib/wasmtime.dll" "$engine/stillfail_engine.dll" "$shell/stillfail_shell.dll" "$A/out/core/core.hbc" "$W/"
  echo "wasm-app: the Windows shell in $((SECONDS - t0)) s"
  if [ "${1:-build}" = run ]; then
    shift
    for kv in "$@"; do export "$kv"; done
    "$W/stillfail.exe" "$(win "$program")"
  fi
  exit 0
fi
if [ "${PLATFORM:-mac}" = ios ]; then
  # iOS's: the shell an app of mbui's iOS host, the app's C and wasmtime (scripts/ios.sh built with MBUI_WASM_THUNKS);
  # on the simulator the app read where it lies on this Mac (MBUI_WASM_APP), so a change of it is no new install of
  # anything; a device's app (MBUI_IOS_SDK=iphoneos) carries it compiled as app.cwasm
  t0=$SECONDS
  MBUI_WASM_THUNKS=$O/thunks.c MBUI_WASM_STUBS="$A/src/sfreplay/trace_files.c" bash "$D/ios.sh" build > "$O/ios.log" 2>&1 \
    || { tail -40 "$O/ios.log"; exit 1; }
  if [ "${MBUI_IOS_SDK:-iphonesimulator}" != iphonesimulator ]; then
    # (Pulley's bytecode, compiled here: the device's wasmtime interprets it, made where there is room to make it)
    wasmtime_cli
    "$WT_CLI" compile $WT_SAME --target pulley64 "$program" -o "$A/out/ios-device/MBUI.app/app.cwasm"
  fi
  echo "wasm-app: the iOS shell in $((SECONDS - t0)) s"
  if [ "${1:-build}" = run ]; then
    shift
    ENV="MBUI_WASM_APP=$program${ENV:+;$ENV}" bash "$D/ios.sh" run "$@"
  fi
  exit 0
fi
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
stubs="src/core/core_native.c src/sfreplay/trace_files.c src/stillfail/core_engine.m"
shell_src=$(cat $host_c $H/*.h $H/wasm_shell.c "$O/thunks.c" $stubs "$moon_root/lib/runtime/runtime.c" "$moon_root/include/moonbit.h" \
  out/core/aarch64-apple-darwin/*.a "$WT/lib/libwasmtime.dylib" "$0" | cksum)
if [ ! -x "$O/shell" ] || [ "$(cat "$O/shell.src" 2>/dev/null)" != "$shell_src" ]; then
  t0=$SECONDS
  # (each source its own object, side by side; none left of another build's, whose names say another MoonBit's runtime)
  rm -rf "$O/obj"
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
