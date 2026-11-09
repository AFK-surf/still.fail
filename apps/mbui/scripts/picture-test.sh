#!/bin/bash
# The new tree and the old view go through the real offscreen renderer. A failed preparation must keep the old PNG.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
mkdir -p out
take=$(mktemp -d "$PWD/out/picture-test.XXXXXXXX")
trap 'rm -rf "$take"' EXIT
APP=sfpicturecheck MODE=release bash scripts/mac.sh build
exe=./_build/native/release/build/stillfail/sfpicturecheck/sfpicturecheck.exe
picture() {
  env MBUI_PICTURE_CHECK="$1" MBUI_PICTURE_CHECK_OUT="$2" "$exe"
}
pixel() {
  ffmpeg -v error -i "$1" -vf 'format=rgb24,crop=1:1:10:10' -frames:v 1 -f rawvideo -pix_fmt rgb24 - |
    od -An -tu1 | awk 'NF >= 3 { print $1, $2, $3; exit }'
}
picture tree "$take/tree.png"
[ "$(pixel "$take/tree.png")" = '255 0 0' ]
picture prepared "$take/prepared.png"
[ "$(pixel "$take/prepared.png")" = '0 255 0' ]
picture time-start "$take/start.png"
picture time-end "$take/end.png"
[ "$(pixel "$take/start.png")" = '255 0 0' ]
[ "$(pixel "$take/end.png")" = '0 255 0' ]
picture time-exact-early "$take/exact-early.png"
picture time-exact-late "$take/exact-late.png"
[ "$(pixel "$take/exact-early.png")" = '255 0 0' ]
[ "$(pixel "$take/exact-late.png")" = '0 255 0' ]
MBUI_NATIVE_INPUT=finger picture native "$take/touch.png"
MBUI_NATIVE_INPUT=mouse picture native "$take/mouse.png"
[ "$(pixel "$take/touch.png")" = '255 0 0' ]
[ "$(pixel "$take/mouse.png")" = '0 255 0' ]
picture frame-start "$take/frame-start.png"
picture frame-middle "$take/frame-middle.png"
[ "$(pixel "$take/frame-start.png")" = '255 0 0' ]
[ "$(pixel "$take/frame-middle.png")" = '0 255 0' ]
picture transparent "$take/transparent.png"
alpha=$(ffmpeg -v error -i "$take/transparent.png" -vf 'format=rgba,crop=1:1:75:75' -frames:v 1 -f rawvideo -pix_fmt rgba - |
  od -An -tu1 | awk 'NF >= 4 { print $4; exit }')
[ "$alpha" = 0 ]
[ "$(pixel "$take/transparent.png")" = '255 0 0' ]
cp "$take/prepared.png" "$take/previous.png"
if picture failed "$take/prepared.png"; then
  echo 'picture-test: failed preparation succeeded' >&2
  exit 1
fi
cmp "$take/prepared.png" "$take/previous.png"
if picture frame-failed "$take/prepared.png" || picture frame-after "$take/prepared.png"; then
  echo 'picture-test: a failed or absent frame succeeded' >&2
  exit 1
fi
cmp "$take/prepared.png" "$take/previous.png"
echo 'picture-test: tree, preparation, time, film frames, transparency and previous picture passed'
