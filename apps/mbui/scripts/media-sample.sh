#!/bin/bash
# The media device catalogue, using real still.fail views drawn separately at each screen's logical size.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
out="$PWD/out/media-sample"
mkdir -p "$out"

APP=sffilm MODE=release bash scripts/mac.sh build
APP=sfmedia MODE=release bash scripts/mac.sh build
film=./_build/native/release/build/stillfail/sffilm/sffilm.exe
demo=./_build/native/release/build/stillfail/sfmedia/sfmedia.exe
capture() {
  info=$(env MBUI_MEDIA_INFO="$1" "$demo")
  [ -n "$info" ] || { echo "media-sample: no screen information for $1" >&2; exit 1; }
  printf '%s\n' "$info" | jq -e '(.width | numbers) > 0 and (.height | numbers) > 0 and (.platform | numbers) >= 0 and (.bars | [.top, .bottom, .left, .right] | all(.[]; type == "number" and . >= 0))' > /dev/null
  size=$(printf '%s' "$info" | jq -r '"\(.width)x\(.height)"')
  platform=$(printf '%s' "$info" | jq -r '.platform')
  bars=$(printf '%s' "$info" | jq -c '{bars}')
  printf 'system %s\nuntil 整理发布清单\nexit\n' "$bars" > "$out/$1.drive"
  env MBUI_FIXTURE=home MBUI_WIN="$size" MBUI_FILM_SCALE=2 MBUI_FILM_PLATFORM="$platform" \
    MBUI_FILM="$out/$1.mp4" MBUI_FILM_LAST="$out/$1.png" \
    MBUI_FILM_DRIVE="$out/$1.drive" "$film"
}
capture phone
capture tablet
capture laptop

printf 'image_ready iphone-11-pro\nimage_ready ipad-pro-11\nimage_ready macbook-pro-16\nimage_ready phone.png\nimage_ready tablet.png\nimage_ready laptop.png\nexit\n' > "$out/catalogue.drive"
env MBUI_WIN=1920x1080 MBUI_FILM_SCALE=1 MBUI_FILM="$out/catalogue.mp4" \
  MBUI_FILM_LAST="$out/catalogue.png" MBUI_FILM_DRIVE="$out/catalogue.drive" \
  MBUI_MEDIA_PHONE="$out/phone.png" MBUI_MEDIA_TABLET="$out/tablet.png" \
  MBUI_MEDIA_LAPTOP="$out/laptop.png" "$demo"
echo "media-sample: $out/catalogue.png"
