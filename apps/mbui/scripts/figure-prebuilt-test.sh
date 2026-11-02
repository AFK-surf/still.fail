#!/bin/bash
# A new workspace can use an already prepared renderer with scene data and without Git, MoonBit or the app's sources.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D/.."
repo=$(cd ../.. && pwd)
exe=${MBUI_FIGURE_RUNTIME:-$PWD/_build/native/release/build/stillfail/sffigure/sffigure.exe}
[ -x "$exe" ] || { echo 'figure-prebuilt-test: build sffigure once before running this test' >&2; exit 1; }
mkdir -p out
take=$(mktemp -d "$PWD/out/figure-prebuilt-test.XXXXXXXX")
trap 'rm -rf "$take"' EXIT
key=0123456789abcdef01234567
artifact="$take/cache/mbui-figure/darwin-arm64-$key"
mkdir -p "$artifact" "$take/client/scripts" "$take/no-tools"
cp "$exe" "$artifact/sffigure"
cp scripts/figure-run.sh "$artifact/figure-run.sh"
printf '{"part":"mbui-figure","target":"darwin-arm64","key":"%s"}\n' "$key" > "$artifact/manifest.json"
cp "$repo/scripts/native.ts" "$repo/scripts/ffmpeg.ts" "$take/client/scripts/"
printf '#!/bin/sh\necho "unexpected build or source lookup" >&2\nexit 91\n' > "$take/no-tools/moon"
cp "$take/no-tools/moon" "$take/no-tools/git"
chmod +x "$take/no-tools/moon" "$take/no-tools/git"
cat > "$take/client/scene.json" <<'JSON'
{"version":1,"width":480,"height":270,"scale":5,"background":"#EDEDF0FF",
 "children":[{"type":"center","children":[{"type":"sign-in-card","width":398,"reverse":false,"key":"clean-wrap"}]}]}
JSON
(
  cd "$take/client"
  unset MBUI_FIGURE_RUNTIME
  export PATH="$take/no-tools:$PATH" STILLFAIL_NATIVE_CACHE="$take/cache" STILLFAIL_NATIVE=offline
  renderer=$(node scripts/native.ts file-key mbui-figure darwin-arm64 "$key")
  [ "$renderer" = "$artifact/sffigure" ]
  bash "$(dirname "$renderer")/figure-run.sh" --scene scene.json picture.png
  if node scripts/native.ts file-key mbui-figure darwin-arm64 bad-key >/dev/null 2>&1; then
    echo 'figure-prebuilt-test: invalid key was accepted' >&2; exit 1
  fi
  if node scripts/native.ts file-key mbui-figure darwin-arm64 111111111111111111111111 >/dev/null 2>&1; then
    echo 'figure-prebuilt-test: a missing version was accepted' >&2; exit 1
  fi
  printf '{"part":"mbui-figure","target":"darwin-arm64","key":"111111111111111111111111"}\n' > "$artifact/manifest.json"
  if node scripts/native.ts file-key mbui-figure darwin-arm64 "$key" >/dev/null 2>&1; then
    echo 'figure-prebuilt-test: a mismatched cached version was accepted' >&2; exit 1
  fi
)
MBUI_FIGURE=wrap-normal MBUI_FIGURE_OUT="$take/reference.png" "$exe"
cmp "$take/client/picture.png" "$take/reference.png"
echo 'figure-prebuilt-test: scene and prebuilt renderer work without a checkout or a compiler'
