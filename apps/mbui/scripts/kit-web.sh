#!/bin/bash
# The component library's page (src/sfstories: each part of src/sf beside its states) built for the browser into OUT,
# as cloud/wrangler.kit.jsonc serves it (kit.monoid.zone): mbui's web host, the app minified as
# scripts/web-app.sh does the app's, the files it carries, and a page that gives them to it before it starts.
#   scripts/kit-web.sh OUT
set -e
D="$(cd "$(dirname "$0")" && pwd)"
out=$(mkdir -p "${1:?scripts/kit-web.sh OUT}" && cd "$1" && pwd)
APP=sfstories bash "$D/web.sh" build >/dev/null
. "$D/env.sh"
ESBUILD=0.28.2
es=$(ls -d "$SF_SRC"/node_modules/.pnpm/esbuild@$ESBUILD/node_modules/esbuild/bin/esbuild 2>/dev/null | tail -1)
if [ -n "$es" ]; then
  "$es" --minify "$MBUI_APP_MOD/out/web/demo.js" --outfile="$out/app.js" --log-level=error
else
  npx --yes esbuild@$ESBUILD --minify "$MBUI_APP_MOD/out/web/demo.js" --outfile="$out/app.js" --log-level=error
fi
cp "$MBUI_DIR/web/host.js" "$out/host.js"
rm -rf "$out/assets"
bash "$D/assets" "$MBUI_APP_MOD" "$out/assets" > /dev/null
# (Inter, the face the app's words are in, as the web's pages carry it; the system's faces draw where it is not there)
inter=$(ls "$SF_SRC"/node_modules/.pnpm/@fontsource-variable+inter@*/node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2 2>/dev/null | tail -1)
[ -z "$inter" ] || cp "$inter" "$out/assets/inter.woff2"
cp "$D/kit.html" "$out/index.html"
ls -la "$out"
gzip -9 -c "$out/app.js" | wc -c | xargs echo "app.js gzip bytes:"
