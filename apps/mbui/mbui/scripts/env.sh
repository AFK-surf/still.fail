# Sourced by the scripts: a toolchain of its own when there is one (MBUI_TOOLS, by default where the development
# machine keeps it), else (Windows, CI, anyone else) the toolchain on PATH as it is.
# In CI, only what the job set up itself (.github/actions/moonbit; MBUI_TOOLS where a job says so): never the
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
# the module's directory: a workspace's (moon.work: an app of a module outside mbui, MBUI_APP_MOD) under its module's
# name.
pkg_build() {
  local mod=
  [ -f moon.work ] && mod=$(sed -n 's/^name *= *"\(.*\)"/\1/p' moon.mod)/
  echo "_build/$2/$3/build/$mod$1"
}

# The photos app's made-up pictures beyond test/images (scripts/test_images.swift --gallery), made once into
# out/pictures on macOS.
gallery_pictures() {
  [ -f out/pictures/big4.heic ] || swift "$(dirname "${BASH_SOURCE[0]}")/test_images.swift" --gallery out/pictures
}
