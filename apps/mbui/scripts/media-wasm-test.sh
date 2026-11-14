#!/bin/bash
# A Wasm still and film carry their real inputs and a failed scene cannot replace a previous result.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D/.."
runtime=${MBUI_MEDIA_RUNTIME:?set MBUI_MEDIA_RUNTIME to the Wasm sffilm launcher}
node tools/wasm-film/compact-test.mjs
mkdir -p out
take=$(mktemp -d "$PWD/out/media-wasm-test.XXXXXXXX")
trap 'rm -rf "$take"' EXIT
printf 'until 整理发布清单\nexit\n' > "$take/pass.drive"
printf 'no-such-step\n' > "$take/fail.drive"
render() {
  env MBUI_FIXTURE=home MBUI_WIN=320x560 MBUI_FILM_SCALE=1 MBUI_NATIVE_INPUT=finger \
    bash scripts/media.sh picture "$take/home.png" "$1"
}
render "$take/pass.drive"
[ -s "$take/home.png" ]
dir=$(dirname "$runtime")
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
jq -e --arg output "$(sha "$take/home.png")" --arg wasm "$(sha "$dir/scene.wasm")" \
  --arg host "$(sha "$dir/native.node")" --arg runner "$(sha "$dir/run.mjs")" \
  --arg compact "$(sha "$dir/compact.mjs")" \
  '.kind == "picture" and .output_sha256 == $output and .settings.fixture == "home" and
   .source.wasm_sha256 == $wasm and .source.host_sha256 == $host and
   .source.runner_sha256 == $runner and .source.compact_sha256 == $compact' \
  "$take/home.png.scene.json" >/dev/null
# A scene drawn though it may break the corner rule (a change's before) says so in its record
env MBUI_FIXTURE=home MBUI_WIN=320x560 MBUI_FILM_SCALE=1 MBUI_NATIVE_INPUT=finger MBUI_FILM_ALLOW_CORNER_FAULTS=1 \
  bash scripts/media.sh picture "$take/kept.png" "$take/pass.drive"
cmp "$take/home.png" "$take/kept.png"
jq -e '.settings.allow_corner_faults == "1"' "$take/kept.png.scene.json" >/dev/null
jq -e '.settings.allow_corner_faults == ""' "$take/home.png.scene.json" >/dev/null
# The made-up station's pace, when given, is in the record; not given, it says none
env MBUI_FIXTURE=home MBUI_WIN=320x560 MBUI_FILM_SCALE=1 MBUI_NATIVE_INPUT=finger MBUI_FIX_PACE=350,600,700 MBUI_FIX_CORE=250 \
  bash scripts/media.sh picture "$take/paced.png" "$take/pass.drive"
jq -e '.settings.fixture_options.fix_pace == "350,600,700" and .settings.fixture_options.fix_core == "250"' \
  "$take/paced.png.scene.json" >/dev/null
jq -e '.settings.fixture_options.fix_pace == "" and .settings.fixture_options.fix_core == ""' "$take/home.png.scene.json" >/dev/null
cp "$take/home.png" "$take/previous.png"
cp "$take/home.png.scene.json" "$take/previous.json"
if render "$take/fail.drive" > "$take/failure.log" 2>&1; then
  echo 'media-wasm-test: a failed scene succeeded' >&2; exit 1
fi
cmp "$take/home.png" "$take/previous.png"
cmp "$take/home.png.scene.json" "$take/previous.json"
for setting in MBUI_PICTURE_FRAME=-1 MBUI_PICTURE_FRAME=1.5 MBUI_FILM_FPS=0.5; do
  if env "$setting" MBUI_MEDIA_RUNTIME="$runtime" MBUI_FIXTURE=home \
    bash scripts/media.sh picture "$take/home.png" "$take/pass.drive" > "$take/failure.log" 2>&1; then
    echo "media-wasm-test: invalid $setting was accepted" >&2; exit 1
  fi
  cmp "$take/home.png" "$take/previous.png"
  cmp "$take/home.png.scene.json" "$take/previous.json"
done
# A film in the same scene: mbui's own film, its frames, last picture and text as the native writer's
env MBUI_FIXTURE=home MBUI_WIN=320x560 MBUI_FILM_SCALE=1 MBUI_NATIVE_INPUT=finger \
  bash scripts/media.sh film "$take/home.mp4" "$take/pass.drive"
[ -s "$take/home.mp4" ] && [ -s "$take/home.mp4.last.png" ] && [ -s "$take/home.mp4.textrec" ]
jq -e --arg output "$(sha "$take/home.mp4")" --arg wasm "$(sha "$dir/scene.wasm")" \
  '.kind == "film" and .output_sha256 == $output and .source.wasm_sha256 == $wasm' "$take/home.mp4.scene.json" >/dev/null
cp "$take/home.mp4" "$take/previous.mp4"
if env MBUI_FIXTURE=home bash scripts/media.sh film "$take/home.mp4" "$take/fail.drive" > "$take/failure.log" 2>&1; then
  echo 'media-wasm-test: a failed film succeeded' >&2; exit 1
fi
cmp "$take/home.mp4" "$take/previous.mp4"
echo 'media-wasm-test: picture, film, source record and failure preservation passed'
