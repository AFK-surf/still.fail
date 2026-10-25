# Sourced by the scripts: a toolchain of its own when there is one (MBUI_TOOLS, by default where the development
# machine keeps it), else (Windows, CI, anyone else) the toolchain on PATH as it is.
# In CI, only what the job set up itself (the repository's .github/actions/mbui-moonbit; MBUI_TOOLS where a job says so): never the
# development machine's toolchain, which a self-hosted runner on that machine (Mini1) would otherwise pick up from
# another's session (2026-10-19: another's moonc).
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  TOOLS=${MBUI_TOOLS:-}
else
  TOOLS=${MBUI_TOOLS:-$HOME/.stillfail/remote/sessions/df5e90815f47b3e730078057bed8feea81b11db927ea4ae88c9346fdc9260bb1/work/tools}
fi
if [ -n "$TOOLS" ] && [ -d "$TOOLS" ]; then
  export MOON_HOME=$TOOLS/moon
  export PATH=$MOON_HOME/bin:$TOOLS/go/bin:$HOME/.local/bin:$PATH
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

# `on_screen COMMAND…`: a command that opens a window (an app run on the host: a shot, a recording, a scripted run)
# run with the machine's screen. Run as a job of a still.fail station (a task another station sent, an agent's job),
# it waits while another task has the screen and gives it back once the command ends (`stillfail-job screen`), so the
# builds and tests around it run beside the other tasks; anywhere else, as it is. What draws offscreen (mbui-render,
# a film, the Tester) needs no screen.
on_screen() {
  if [ -n "${STILLFAIL_JOB_SCREEN:-}" ] && command -v stillfail-job > /dev/null; then stillfail-job screen "$@"; else "$@"; fi
}
