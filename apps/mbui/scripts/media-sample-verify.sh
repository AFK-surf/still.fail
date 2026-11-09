#!/bin/bash
# Verify that the catalogue's application images use each device's screen and its system bars.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D/.."
demo=./_build/native/release/build/stillfail/sfmedia/sfmedia.exe
for model in phone tablet laptop; do
  info=$(env MBUI_MEDIA_INFO="$model" "$demo")
  [ -n "$info" ] || { echo "media-sample: no screen information for $model" >&2; exit 1; }
  width=$(printf '%s\n' "$info" | jq -er '.width * 2')
  height=$(printf '%s\n' "$info" | jq -er '.height * 2')
  bars=$(printf '%s\n' "$info" | jq -c '.bars')
  actual=$(sips -g pixelWidth -g pixelHeight "out/media-sample/$model.png" | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w "x" h}')
  [ "$actual" = "${width}x${height}" ] || { echo "media-sample: $model is $actual, expected ${width}x${height}" >&2; exit 1; }
  first=$(sed -n '1p' "out/media-sample/$model.drive")
  [ "$first" = "system {\"bars\":$bars}" ] || { echo "media-sample: $model did not use its system bars" >&2; exit 1; }
done
echo 'media-sample: screen sizes and system bars match all three models'
