#!/bin/bash
# The component library's page (src/sfstories: each part of src/sf beside its states) built for the browser into OUT,
# as cloud/wrangler.kit.jsonc serves it (kit.monoid.zone): mbui's web host, the app minified as mbui's scripts/web.sh
# bundle does, the files it carries, the sources it shows, and a page that gives them to it before it starts.
#   scripts/kit-web.sh OUT
set -e
D="$(cd "$(dirname "$0")" && pwd)"
out=$(mkdir -p "${1:?scripts/kit-web.sh OUT}" && cd "$1" && pwd)
. "$D/env.sh"
rm -rf "$out/assets"
bash "$D/assets" "$MBUI_APP_MOD" "$out/assets" > /dev/null
# (Inter, the face the app's words are in, as the web's pages carry it; the system's faces draw where it is not there)
inter=$(ls "$SF_SRC"/node_modules/.pnpm/@fontsource-variable+inter@*/node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2 2>/dev/null | tail -1)
[ -z "$inter" ] || cp "$inter" "$out/assets/inter.woff2"
# (the sources the page shows: stories.mbt, whose lines each state's code is cut from, and each file of the library
# it names, whose functions it lists; each after a line naming it, src/sfstories/sources.mbt)
(cd "$MBUI_APP_MOD/src" && for f in sfstories/stories.mbt $(grep -o '"[a-z_]*\.mbt"' sfstories/stories.mbt | tr -d '"' | sort -u | sed 's|^|sf/|'); do
  [ -f "$f" ] || continue
  printf '//@@ %s\n' "$f"
  cat "$f"
done) > "$out/assets/sources.txt"
cp "$D/kit.html" "$out/index.html"
APP=sfstories MBUI_WEB_BROTLI=0 exec bash "$MBUI_DIR/scripts/web.sh" bundle "$out"
