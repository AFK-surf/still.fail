#!/bin/bash
# A prebuilt application scene renderer takes only the drive and produces the same records without a checkout.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D/.."
repo=$(cd ../.. && pwd)
exe=${MBUI_MEDIA_RUNTIME:-$PWD/_build/native/release/build/stillfail/sffilm/sffilm.exe}
[ -x "$exe" ] || { echo 'media-prebuilt-test: build sffilm once before running this test' >&2; exit 1; }
mkdir -p out
take=$(mktemp -d "$PWD/out/media-prebuilt-test.XXXXXXXX")
trap 'rm -rf "$take"' EXIT
key=abcdef0123456789abcdef01
artifact="$take/cache/mbui-film/darwin-arm64-$key"
mkdir -p "$artifact" "$take/client/scripts" "$take/no-tools"
cp "$exe" "$artifact/sffilm"
cp scripts/media.sh "$artifact/media.sh"
printf '{"part":"mbui-film","target":"darwin-arm64","key":"%s","commit":"test-revision"}\n' "$key" > "$artifact/manifest.json"
cp "$repo/scripts/native.ts" "$repo/scripts/ffmpeg.ts" "$take/client/scripts/"
printf '#!/bin/sh\necho "unexpected build or source lookup" >&2\nexit 91\n' > "$take/no-tools/moon"
cp "$take/no-tools/moon" "$take/no-tools/git"
chmod +x "$take/no-tools/moon" "$take/no-tools/git"
printf 'until 整理发布清单\nexit\n' > "$take/client/pass.drive"
printf 'no-such-step\n' > "$take/client/fail.drive"
(
  cd "$take/client"
  unset MBUI_MEDIA_RUNTIME
  export PATH="$take/no-tools:$PATH" STILLFAIL_NATIVE_CACHE="$take/cache" STILLFAIL_NATIVE=offline
  export MBUI_FIXTURE=home MBUI_WIN=320x560 MBUI_FILM_SCALE=1
  renderer=$(node scripts/native.ts file-key mbui-film darwin-arm64 "$key")
  [ "$renderer" = "$artifact/sffilm" ]
  bash "$(dirname "$renderer")/media.sh" picture picture.png pass.drive
  jq -e --arg key "$key" '.source.runtime_key == $key and .source.revision == "test-revision" and .source.dirty == "unknown"' picture.png.scene.json >/dev/null
  cp picture.png previous.png
  cp picture.png.scene.json previous.scene.json
  if bash "$(dirname "$renderer")/media.sh" picture picture.png fail.drive; then
    echo 'media-prebuilt-test: a failed drive succeeded' >&2; exit 1
  fi
  cmp previous.png picture.png
  cmp previous.scene.json picture.png.scene.json
  bash "$(dirname "$renderer")/media.sh" film film.mp4 pass.drive
  [ -s film.mp4 ] && [ -s film.mp4.last.png ] && [ -s film.mp4.textrec ]
  jq -e --arg key "$key" '.kind == "film" and .source.runtime_key == $key' film.mp4.scene.json >/dev/null
)
echo 'media-prebuilt-test: picture, film, records and failure preservation work without a checkout or a compiler'
