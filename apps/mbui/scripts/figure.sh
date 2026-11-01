#!/bin/bash
# Build once and render one or several named mbui share graphics without a window or movie encoder.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
usage='figure.sh NAME OUTPUT.png [FONT] | figure.sh --batch OUTPUT_DIR NAME...'
[ "$#" -ge 2 ] || { echo "$usage" >&2; exit 2; }
mode=one
font=${MBUI_FIGURE_FONT:-}
if [ "$1" = --batch ]; then
  [ "$#" -ge 3 ] || { echo "$usage" >&2; exit 2; }
  mode=batch
  outdir=$2
  shift 2
  seen=''
  for name in "$@"; do
    case "$name" in ''|*[!A-Za-z0-9_-]*) echo "figure: invalid name $name" >&2; exit 2 ;; esac
    case " $seen " in *" $name "*) echo "figure: repeated name $name" >&2; exit 2 ;; esac
    seen="$seen $name"
  done
  case "$outdir" in /*) ;; *) outdir="$PWD/$outdir" ;; esac
  mkdir -p "$outdir"
else
  [ "$#" -le 3 ] || { echo "$usage" >&2; exit 2; }
  name=$1
  out=$2
  font=${3:-$font}
  case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
fi
if [ -n "$font" ]; then case "$font" in /*) ;; *) font="$PWD/$font" ;; esac; fi
APP=sffigure MODE=release bash "$D/mac.sh" build
exe=./_build/native/release/build/stillfail/sffigure/sffigure.exe
if [ "$mode" = batch ]; then
  # Render every image before publishing any: one bad scene keeps all the previous pictures.
  tmpdir=$(mktemp -d "$outdir/.figure-batch.XXXXXXXX")
  trap 'rm -rf "$tmpdir"' EXIT
  names=$(IFS=,; printf '%s' "$*")
  MBUI_FIGURE_BATCH="$names" MBUI_FIGURE_DIR="$tmpdir" MBUI_FIGURE_FONT="$font" "$exe"
  for name in "$@"; do
    mv -f "$tmpdir/$name.png" "$outdir/$name.png"
    echo "figure: $outdir/$name.png"
  done
  rm -rf "$tmpdir"
  trap - EXIT
else
  # Write beside the destination first: a failed render must not leave a partial PNG at the requested path.
  tmp=$(mktemp "${out}.tmp.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  MBUI_FIGURE_BATCH= MBUI_FIGURE="$name" MBUI_FIGURE_OUT="$tmp" MBUI_FIGURE_FONT="$font" "$exe"
  mv -f "$tmp" "$out"
  trap - EXIT
  echo "figure: $out"
fi
