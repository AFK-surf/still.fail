#!/bin/bash
# A failed image or unrenderable native view must not be published as an apparently complete film.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D/.."
mkdir -p out
take=$(mktemp -d "$PWD/out/film-assets-test.XXXXXXXX")
trap 'rm -rf "$take"' EXIT
APP=sffilmcheck MODE=release bash scripts/mac.sh build
exe=./_build/native/release/build/stillfail/sffilmcheck/sffilmcheck.exe
film() {
  env MBUI_FILM_CHECK_MODE="$1" MBUI_FILM_CHECK_OUT="$take/film.mp4" \
    MBUI_FILM_CHECK_ALLOW="${MBUI_FILM_CHECK_ALLOW:-}" "$exe"
}
film good
cp "$take/film.mp4" "$take/previous.mp4"
for mode in ${FILM_ASSET_MODES:-missing late-missing native}; do
  case "$mode" in missing|late-missing) reason='image could not be decoded' ;; native) reason='native view content cannot be drawn offscreen' ;;
    *) echo "film-assets-test: unknown mode $mode" >&2; exit 2 ;; esac
  if film "$mode" > "$take/$mode.log" 2>&1; then
    echo "film-assets-test: $mode content was silently omitted" >&2
    exit 1
  fi
  rg -q "$reason" "$take/$mode.log" || { cat "$take/$mode.log"; exit 1; }
  cmp "$take/film.mp4" "$take/previous.mp4"
done
MBUI_FILM_CHECK_ALLOW=1 film native

# The public entry point must preserve the movie and its sidecars too, including when a later frame fails.
printf 'exit\n' > "$take/drive"
media() {
  env MBUI_MEDIA_APP=sffilmcheck MBUI_FILM_CHECK_RUN=1 MBUI_FILM_CHECK_MODE="$1" \
    MBUI_WIN=128x128 MBUI_FILM_SCALE=1 MBUI_FILM_ALLOW_INCOMPLETE="${MBUI_FILM_ALLOW_INCOMPLETE:-}" \
    bash scripts/media.sh film "$take/media.mp4" "$take/drive"
}
media good
for suffix in '' .last.png .textrec .scene.json; do cp "$take/media.mp4$suffix" "$take/previous-media$suffix"; done
for mode in missing late-missing native; do
  case "$mode" in
    late-missing) printf 'tap Reveal\nexit\n' > "$take/drive" ;;
    *) printf 'exit\n' > "$take/drive" ;;
  esac
  if media "$mode" > "$take/media-$mode.log" 2>&1; then
    echo "film-assets-test: media accepted $mode content" >&2
    exit 1
  fi
  case "$mode" in
    missing|late-missing) reason='image could not be decoded' ;;
    native) reason='native view content cannot be drawn offscreen' ;;
  esac
  rg -q "$reason" "$take/media-$mode.log" || { cat "$take/media-$mode.log"; exit 1; }
  for suffix in '' .last.png .textrec .scene.json; do cmp "$take/media.mp4$suffix" "$take/previous-media$suffix"; done
done
MBUI_FILM_ALLOW_INCOMPLETE=1 media native
jq -e '.settings.allow_incomplete == "1"' "$take/media.mp4.scene.json" >/dev/null
echo 'film-assets-test: incomplete frames fail without replacing the film or sidecars; explicit omission is recorded'
