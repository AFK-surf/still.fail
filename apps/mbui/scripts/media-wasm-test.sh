#!/bin/bash
# A Wasm still carries its real inputs and a failed scene cannot replace a previous result.
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
cp "$take/home.png" "$take/previous.png"
cp "$take/home.png.scene.json" "$take/previous.json"
if render "$take/fail.drive"; then
  echo 'media-wasm-test: a failed scene succeeded' >&2; exit 1
fi
cmp "$take/home.png" "$take/previous.png"
cmp "$take/home.png.scene.json" "$take/previous.json"
for setting in MBUI_PICTURE_FRAME=-1 MBUI_PICTURE_FRAME=1.5 MBUI_FILM_FPS=0.5; do
  if env "$setting" MBUI_MEDIA_RUNTIME="$runtime" MBUI_FIXTURE=home \
    bash scripts/media.sh picture "$take/home.png" "$take/pass.drive"; then
    echo "media-wasm-test: invalid $setting was accepted" >&2; exit 1
  fi
  cmp "$take/home.png" "$take/previous.png"
  cmp "$take/home.png.scene.json" "$take/previous.json"
done
echo 'media-wasm-test: picture, source record and failure preservation passed'
