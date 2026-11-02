#!/bin/bash
# The prebuilt renderer takes a scene as data: changing it changes the picture without rebuilding the renderer.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D/.."
exe=${MBUI_FIGURE_RUNTIME:-$PWD/_build/native/release/build/stillfail/sffigure/sffigure.exe}
[ -x "$exe" ] || { echo 'figure-scene-test: build sffigure once before running this test' >&2; exit 1; }
mkdir -p out
take=$(mktemp -d "$PWD/out/figure-scene-test.XXXXXXXX")
trap 'rm -rf "$take"' EXIT

cat > "$take/scene.json" <<'JSON'
{"version":1,"width":480,"height":270,"scale":5,"background":"#EDEDF0FF",
 "children":[{"type":"center","children":[{"type":"sign-in-card","width":398,"reverse":false,"key":"clean-wrap"}]}]}
JSON
MBUI_FIGURE_RUNTIME="$exe" bash scripts/figure.sh --scene "$take/scene.json" "$take/scene.png"
MBUI_FIGURE=wrap-normal MBUI_FIGURE_OUT="$take/reference.png" "$exe"
cmp "$take/reference.png" "$take/scene.png"

perl -pi -e 's#"reverse":false#"reverse":true#' "$take/scene.json"
MBUI_FIGURE_RUNTIME="$exe" bash scripts/figure.sh --scene "$take/scene.json" "$take/scene.png"
MBUI_FIGURE=wrap-reverse MBUI_FIGURE_OUT="$take/reference.png" "$exe"
cmp "$take/reference.png" "$take/scene.png"

cp "$take/scene.png" "$take/previous.png"
printf '%s\n' '{"version":1,"width":480,"height":270,"scale":5,"background":"#EDEDF0FF","children":[{"type":"unknown"}]}' > "$take/scene.json"
if MBUI_FIGURE_RUNTIME="$exe" bash scripts/figure.sh --scene "$take/scene.json" "$take/scene.png"; then
  echo 'figure-scene-test: an unknown scene component was accepted' >&2
  exit 1
fi
cmp "$take/previous.png" "$take/scene.png"
printf '%s\n' '{"version":1,"width":480,"height":270,"scale":5,"background":"#EDEDF0FF","children":[{"type":"sign-in-card","width":398,"key":"card","shadow":true}]}' > "$take/scene.json"
if MBUI_FIGURE_RUNTIME="$exe" bash scripts/figure.sh --scene "$take/scene.json" "$take/scene.png"; then
  echo 'figure-scene-test: an unknown component property was silently ignored' >&2
  exit 1
fi
cmp "$take/previous.png" "$take/scene.png"
echo 'figure-scene-test: prebuilt runtime renders the real card from scene data and preserves output on error'
