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
  env MBUI_FIXTURE=home MBUI_WIN=320x560 MBUI_FILM_SCALE=1 MBUI_FILM_FPS="${MBUI_FILM_FPS:-60}" \
    MBUI_FILM_PREPARE="${MBUI_FILM_PREPARE:-}" \
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

if MBUI_FILM_PREPARE="$take/pass.drive" film "$take/fail.drive" "$take/last.png"; then
  echo "film-test: a passed preparation hid a failed drive" >&2
  exit 1
fi
if MBUI_FILM_PREPARE="$take/fail.drive" film "$take/pass.drive" "$take/last.png"; then
  echo "film-test: a failed preparation succeeded" >&2
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
printf 'until 整理发布清单\ntap 整理发布清单\nexit\n' > "$take/prepare.drive"
printf 'until 推送截图前要先登录 gh。\nexit\n' > "$take/prepared.drive"
MBUI_FILM_PREPARE="$take/prepare.drive" film "$take/prepared.drive" "$take/last.png"
# The image and the film use the very same application, settings, preparation and actions. Compare their
# uncompressed pixels, before H.264 encoding: this also checks that both choose the same final frame.
env MBUI_FIXTURE=home MBUI_WIN=320x560 MBUI_FILM_SCALE=1 MBUI_FILM_PREPARE="$take/prepare.drive" \
  MBUI_FILM_DRIVE="$take/prepared.drive" MBUI_PICTURE="$take/picture.png" "$exe"
ffmpeg -v error -i "$take/last.png" -frames:v 1 -f rawvideo -pix_fmt rgba "$take/last.rgba"
ffmpeg -v error -i "$take/picture.png" -frames:v 1 -f rawvideo -pix_fmt rgba "$take/picture.rgba"
cmp "$take/last.rgba" "$take/picture.rgba"
cp "$take/picture.png" "$take/previous-picture.png"
if env MBUI_FIXTURE=home MBUI_WIN=320x560 MBUI_FILM_SCALE=1 MBUI_FILM_DRIVE="$take/fail.drive" \
  MBUI_PICTURE="$take/picture.png" "$exe"; then
  echo "film-test: a failed picture script succeeded" >&2
  exit 1
fi
cmp "$take/picture.png" "$take/previous-picture.png"
MBUI_FILM_FPS=120 film "$take/pass.drive" "$take/last.png"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate \
  -of csv=p=0 "$take/film.mp4" | rg -q '^320,560,120/1$'
cp "$take/film.mp4" "$take/previous-120.mp4"
if MBUI_FILM_FPS=0 film "$take/pass.drive" "$take/last.png"; then
  echo "film-test: an invalid frame rate succeeded" >&2
  exit 1
fi
cmp "$take/film.mp4" "$take/previous-120.mp4"
echo "film-test: a failed run keeps the previous movie and pictures"
