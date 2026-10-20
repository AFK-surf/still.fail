# Sourced by apps/mbui's scripts: mbui (scripts/mbui.sh: the commit mbui.rev pins, linked at apps/mbui/mbui) and its
# toolchain setup (mbui's scripts/env.sh: MBUI_TOOLS, else MoonBit on PATH); then, for mbui's scripts, this module as
# the app's (MBUI_APP_MOD) and this checkout as still.fail's sources the core is built from (EMBER).
A=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MBUI_DIR=$(sh "$A/scripts/mbui.sh") || { echo "apps/mbui: no mbui (scripts/mbui.sh)" >&2; exit 1; }
. "$MBUI_DIR/scripts/env.sh"
export MBUI_DIR
export MBUI_APP_MOD=$A
export EMBER=${EMBER:-$(cd "$A/../.." && pwd)}
# (scripts/core.sh's Rust shell, for the macOS apps with the core: a target of this module's own)
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$A/out/core-target}
