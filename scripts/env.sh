# Sourced by the scripts: a toolchain of its own when there is one (MBUI_TOOLS, by default where the development
# machine keeps it), else (Windows, CI, anyone else) the toolchain on PATH as it is.
TOOLS=${MBUI_TOOLS:-$HOME/.stillfail/remote/sessions/df5e90815f47b3e730078057bed8feea81b11db927ea4ae88c9346fdc9260bb1/work/tools}
if [ -d "$TOOLS" ]; then
  export MOON_HOME=$TOOLS/moon
  export PATH=$MOON_HOME/bin:$TOOLS/go/bin:$HOME/.local/bin:$PATH
fi

# The photos app's made-up pictures beyond test/images (scripts/test_images.swift --gallery), made once into
# out/pictures on macOS.
gallery_pictures() {
  [ -f out/pictures/big4.heic ] || swift "$(dirname "${BASH_SOURCE[0]}")/test_images.swift" --gallery out/pictures
}
