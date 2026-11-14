# Sourced by apps/mbui's scripts: mbui (libs/mbui: scripts/mbui.sh says where) and its
# toolchain setup (mbui's scripts/env.sh: MBUI_TOOLS, else MoonBit on PATH); then, for mbui's scripts, this module as
# the app's (MBUI_APP_MOD) and this checkout as still.fail's sources the core is built from (SF_SRC).
A=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# (still.fail's build station keeps its MoonBit at ~/stillfail-ci/mbui/tools, and a station task's shell has no moon on
# PATH: taken when nothing else is, so a picture's renderer builds there without being told; CI sets up its own)
if [ -z "${MBUI_TOOLS:-}" ] && [ -z "${GITHUB_ACTIONS:-}" ] && ! command -v moon > /dev/null \
  && [ -d "$HOME/stillfail-ci/mbui/tools/moon" ]; then
  export MBUI_TOOLS=$HOME/stillfail-ci/mbui/tools
fi
MBUI_DIR=$(sh "$A/scripts/mbui.sh") || { echo "apps/mbui: no mbui (scripts/mbui.sh)" >&2; exit 1; }
. "$MBUI_DIR/scripts/env.sh"
export MBUI_DIR
export MBUI_APP_MOD=$A
export SF_SRC=${SF_SRC:-$(cd "$A/../.." && pwd)}
# (scripts/core.sh's Rust shell, for the macOS apps with the core: a target of this module's own)
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$A/out/core-target}
# (a window this machine's station shares among its tasks: a task's command that opens one waits for the screen,
# mbui's on_screen)
if [ -z "${MBUI_ON_SCREEN:-}" ] && [ -n "${STILLFAIL_JOB_SCREEN:-}" ] && command -v stillfail-job > /dev/null; then
  export MBUI_ON_SCREEN="stillfail-job screen"
fi
