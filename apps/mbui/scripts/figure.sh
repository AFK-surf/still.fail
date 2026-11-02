#!/bin/bash
# Build the renderer when needed, or use a prebuilt runtime, then render one or several mbui graphics.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
usage='figure.sh NAME OUTPUT.png [FONT] | figure.sh --scene SCENE.json OUTPUT.png | figure.sh --batch OUTPUT_DIR NAME...'
[ "$#" -ge 2 ] || { echo "$usage" >&2; exit 2; }
if [ "$1" = --scene ]; then
  [ "$#" -eq 3 ] && [ -s "$2" ] || { echo "$usage" >&2; exit 2; }
elif [ "$1" = --batch ]; then
  [ "$#" -ge 3 ] || { echo "$usage" >&2; exit 2; }
else
  [ "$#" -le 3 ] || { echo "$usage" >&2; exit 2; }
fi
if [ -z "${MBUI_FIGURE_RUNTIME:-}" ]; then
  APP=sffigure MODE=release bash "$D/mac.sh" build
  MBUI_FIGURE_RUNTIME="$A/_build/native/release/build/stillfail/sffigure/sffigure.exe"
fi
export MBUI_FIGURE_RUNTIME
exec bash "$D/figure-run.sh" "$@"
