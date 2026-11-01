#!/bin/bash
# Build and render a named mbui share graphic, without opening a window or encoding a movie.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
name=${1:?figure name (wrap)}
out=${2:?output PNG path}
font=${3:-}
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
if [ -n "$font" ]; then case "$font" in /*) ;; *) font="$PWD/$font" ;; esac; fi
APP=sffigure MODE=release bash "$D/mac.sh" build
# Write beside the destination first: a failed render must not leave a partial PNG at the requested path.
tmp=$(mktemp "${out}.tmp.XXXXXX")
trap 'rm -f "$tmp"' EXIT
MBUI_FIGURE="$name" MBUI_FIGURE_OUT="$tmp" MBUI_FIGURE_FONT="$font" \
  ./_build/native/release/build/stillfail/sffigure/sffigure.exe
mv -f "$tmp" "$out"
trap - EXIT
echo "figure: $out"
