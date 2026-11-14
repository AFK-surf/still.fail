# Sourced by the scripts: use an explicitly selected toolchain, or leave the toolchain on PATH as it is.
# CI sets up its own toolchain with .github/actions/mbui-moonbit; it must not pick up another session's tools.
TOOLS=${MBUI_TOOLS:-}
if [ -n "$TOOLS" ] && [ -d "$TOOLS" ]; then
  export MOON_HOME=$TOOLS/moon
  export PATH=$MOON_HOME/bin:$TOOLS/go/bin:$HOME/.local/bin:$PATH
fi

# Keep the compact MoonBit entry point on PATH for child shells and `env moon` too. Record the toolchain before
# adding it, so callers looking for the runtime never mistake the wrapper for the MoonBit installation.
MBUI_MOON_BIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/moon-bin" && pwd)
if [ -n "${MOON_HOME:-}" ] && [ -x "$MOON_HOME/bin/moon" ]; then
  export MBUI_REAL_MOON="$MOON_HOME/bin/moon"
elif [ "$(command -v moon || true)" != "$MBUI_MOON_BIN/moon" ]; then
  export MBUI_REAL_MOON=$(command -v moon || true)
fi
if [ -n "${MBUI_REAL_MOON:-}" ]; then
  export MOON_HOME=${MOON_HOME:-$(dirname "$(dirname "$MBUI_REAL_MOON")")}
  export PATH="$MBUI_MOON_BIN:$PATH"
fi

# Where moon builds package $1 (its directory under src) for target $2 (native, js) in mode $3 (release, debug), from
# the module's directory: a workspace's of more than one module (moon.work: an app of a module beside mbui,
# MBUI_APP_MOD) under its module's name; mbui's own (moon.work, itself alone: kept from the app's workspace above it in
# the repository) as a module's.
pkg_build() {
  local mod=
  [ -f moon.work ] && [ "$(grep -c '^ *"' moon.work)" -gt 1 ] && mod=$(sed -n 's/^name *= *"\(.*\)"/\1/p' moon.mod)/
  echo "_build/$2/$3/build/$mod$1"
}

# The photos app's made-up pictures beyond test/images (scripts/test_images.swift --gallery), made once into
# out/pictures on macOS.
gallery_pictures() {
  [ -f out/pictures/big4.heic ] || swift "$(dirname "${BASH_SOURCE[0]}")/test_images.swift" --gallery out/pictures
}

# The native tests built as the apps are: --release, moonc's C split and compiled in parallel by scripts/mbc (its
# shim moon's cc on PATH), the units made of the same inputs (by content) kept in MBC_STORE and compiled once for every
# test that has them. `native_tests [DIR]` (the module's directory, the current one by default) sets that up; then
# `moon test $NATIVE …`. clang where there is one (MBC_REAL_CC says otherwise; Windows: the cl on PATH); without ThinLTO
# unless MBC_LTO says.
native_tests() {
  local root=${1:-$PWD}
  unset MOON_CC
  if [ "$(uname -s | cut -c1-5)" != MINGW ] && [ "$(uname -s | cut -c1-4)" != MSYS ]; then
    export MBC_REAL_CC=${MBC_REAL_CC:-$(command -v clang || command -v cc)}
  fi
  export MBC_LTO=${MBC_LTO:-0}
  export MBC_STORE=${MBC_STORE:-$root/_build/native/release/mbc-store}
  PATH="$("$(dirname "${BASH_SOURCE[0]}")/mbc" shim "$root/_build/mbc-bin"):$PATH"
  NATIVE="--target native --release"
}

# `moon_test_native ARGS…`: `moon test ARGS…` on native as native_tests sets it up, in the current module's directory
# (in a subshell: nothing else of the script's environment changed).
moon_test_native() { ( native_tests "$PWD"; moon test $NATIVE "$@" ); }

# `moon_tests ARGS…`: `moon test ARGS…` as development runs it, on wasm-gc (--release, as native's: no C compiled, the
# user 2026-11-03; wasm-gc rather than classic Wasm, whose memory, freed by counting alone, never frees what holds
# itself), and in CI (GITHUB_ACTIONS) or with MBUI_NATIVE_TESTS=1 on native as moon_test_native does.
moon_tests() {
  if [ -n "${GITHUB_ACTIONS:-}" ] || [ "${MBUI_NATIVE_TESTS:-}" = 1 ]; then moon_test_native "$@"
  else moon test --target wasm-gc --release "$@"; fi
}

# `on_screen COMMAND…`: a command that opens a window (an app run on the host: a shot, a recording, a scripted run)
# run with the machine's screen: through MBUI_ON_SCREEN where the machine shares its screen among tasks (a command
# that waits while another task has it and gives it back once the command ends: still.fail's apps/mbui/scripts/env.sh
# names its station's), so the builds and tests around it run beside the other tasks; anywhere else, as it is. What
# draws offscreen (mbui-render, a film, the Tester) needs no screen.
on_screen() {
  if [ -n "${MBUI_ON_SCREEN:-}" ]; then $MBUI_ON_SCREEN "$@"; else "$@"; fi
}

# The objects of an app's Wasm shell (scripts/android.sh, ios.sh with MBUI_WASM_THUNKS: no C of moonc's to split),
# each source its own, compiled side by side, kept while the command, the source and what its depfile says it included
# are as they were. `shell_objs DIR CC CFLAGS OBJC_FLAGS FILE…` prints the objects.
shell_objs() {
  local dir=$1 cc=$2 cflags=$3 objc=$4 f o flags pids=()
  shift 4
  mkdir -p "$dir"
  for f in "$@"; do
    o=$dir/$(echo "$f" | tr '/' '_').o
    echo "$o"
    flags=$cflags
    case $f in *.m) flags="$flags $objc" ;; esac
    [ -f "$o" ] && [ "$(cat "$o.sum" 2>/dev/null)" = "$(shell_obj_sum "$cc $flags" "$f" "$o")" ] && continue
    (rm -f "$o.sum"; $cc $flags -MD -MF "$o.d" -c "$f" -o "$o" >&2 && shell_obj_sum "$cc $flags" "$f" "$o" > "$o.sum") &
    pids+=($!)
  done
  for p in ${pids[@]+"${pids[@]}"}; do wait "$p" || return 1; done
}

# (what object $3 of source $2 is made of: command $1, the source and what its depfile says it included)
shell_obj_sum() {
  (echo "$1"; cat "$2" $(sed -e '1d' -e 's/\\$//' "$3.d" 2>/dev/null | tr ' ' '\n' | grep -v '^$' | sort -u) 2>/dev/null) |
    shasum | cut -c1-40
}
