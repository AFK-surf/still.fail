#!/bin/bash
# The record must describe the actual outputs, and a failed scene must not replace a previous result or its record.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D/.."
mkdir -p out
take=$(mktemp -d "$PWD/out/media-test.XXXXXXXX")
trap 'rm -rf "$take"' EXIT
printf 'until 整理发布清单\nexit\n' > "$take/pass.drive"
printf 'no-such-step\n' > "$take/fail.drive"
render() {
  env MBUI_FIXTURE=home MBUI_WIN=320x560 MBUI_FILM_SCALE=1 MBUI_NATIVE_INPUT=finger \
    MBUI_MEDIA_RECORD='{"purpose":"fixture"}' bash scripts/media.sh "$@"
}
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
render picture "$take/home.png" "$take/pass.drive"
jq -e --arg sha "$(sha "$take/home.png")" \
  '.kind == "picture" and .output_sha256 == $sha and .settings.fixture == "home" and
   .settings.native_input == "finger" and .extra.purpose == "fixture" and
   (.source.executable_sha256 | length) == 64' "$take/home.png.scene.json" >/dev/null
jq -j '.drive.text' "$take/home.png.scene.json" > "$take/recorded.drive"
cmp "$take/pass.drive" "$take/recorded.drive"
cp "$take/home.png" "$take/previous.png"
cp "$take/home.png.scene.json" "$take/previous.json"
if render picture "$take/home.png" "$take/fail.drive"; then
  echo 'media-test: a failed scene succeeded' >&2
  exit 1
fi
cmp "$take/home.png" "$take/previous.png"
cmp "$take/home.png.scene.json" "$take/previous.json"
render film "$take/home.mp4" "$take/pass.drive"
jq -e --arg film "$(sha "$take/home.mp4")" --arg last "$(sha "$take/home.mp4.last.png")" \
  --arg text "$(sha "$take/home.mp4.textrec")" \
  '.kind == "film" and .output_sha256 == $film and .last_frame_sha256 == $last and .text_record_sha256 == $text' \
  "$take/home.mp4.scene.json" >/dev/null
cp "$take/home.mp4" "$take/previous.mp4"
cp "$take/home.mp4.scene.json" "$take/previous-film.json"
cp "$take/home.mp4.last.png" "$take/previous-last.png"
cp "$take/home.mp4.textrec" "$take/previous.textrec"
if render film "$take/home.mp4" "$take/fail.drive"; then
  echo 'media-test: a failed film succeeded' >&2
  exit 1
fi
cmp "$take/home.mp4" "$take/previous.mp4"
cmp "$take/home.mp4.scene.json" "$take/previous-film.json"
cmp "$take/home.mp4.last.png" "$take/previous-last.png"
cmp "$take/home.mp4.textrec" "$take/previous.textrec"
if find "$take" -name '*.media.*' -print | rg -q .; then
  echo 'media-test: a temporary render was left behind' >&2
  exit 1
fi
echo 'media-test: picture, film, scene records and failure preservation passed'
