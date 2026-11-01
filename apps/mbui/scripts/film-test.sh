#!/bin/bash
# A real offscreen film, then two failed runs targeting the same files. A failure must report itself and leave the
# previous movie, its last picture, and its text record in place.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
mkdir -p out
take=$(mktemp -d "$PWD/out/film-test.XXXXXXXX")
trap 'rm -rf "$take"' EXIT

APP=sffilm MODE=release bash scripts/mac.sh build
exe=./_build/native/release/build/stillfail/sffilm/sffilm.exe
printf 'until 整理发布清单\nexit\n' > "$take/pass.drive"
printf 'no-such-step\n' > "$take/fail.drive"
film() {
  env MBUI_FIXTURE=home MBUI_WIN=320x560 MBUI_FILM_SCALE=1 \
    MBUI_FILM="$take/film.mp4" MBUI_FILM_DRIVE="$1" MBUI_FILM_LAST="$2" "$exe"
}

film "$take/pass.drive" "$take/last.png"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate \
  -of csv=p=0 "$take/film.mp4" | rg -q '^320,560,60/1$'
cp "$take/film.mp4" "$take/previous.mp4"
cp "$take/film.mp4.textrec" "$take/previous.textrec"
cp "$take/last.png" "$take/previous.png"

if film "$take/fail.drive" "$take/last.png"; then
  echo "film-test: a failed drive succeeded" >&2
  exit 1
fi
cmp "$take/film.mp4" "$take/previous.mp4"
cmp "$take/film.mp4.textrec" "$take/previous.textrec"
cmp "$take/last.png" "$take/previous.png"

if film "$take/pass.drive" "$take/missing/last.png"; then
  echo "film-test: a failed picture succeeded" >&2
  exit 1
fi
cmp "$take/film.mp4" "$take/previous.mp4"
cmp "$take/film.mp4.textrec" "$take/previous.textrec"
if find "$take" -name '*.tmp.mp4' -print | rg -q .; then
  echo "film-test: a failed take left a temporary movie" >&2
  exit 1
fi
echo "film-test: a failed run keeps the previous movie and pictures"
