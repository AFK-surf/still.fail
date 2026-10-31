#!/bin/bash
# still.fail's app in a browser, on the web's own core (web/mbui.html, web/src/mbui/core.ts): the app built for the
# browser (scripts/web.sh, APP=stillfail) and mbui's web host put where the web's build serves them, web/public/mbui
# (ignored); `pnpm run build:cloud` (or `pnpm dev:web`) then serves it at /mbui.html.
#   scripts/web-app.sh
set -e
D="$(cd "$(dirname "$0")" && pwd)"
APP=stillfail bash "$D/web.sh" build >/dev/null
. "$D/env.sh"
out=$EMBER/web/public/mbui
mkdir -p "$out"
# minified by the web's own esbuild where its packages are installed (MoonBit's names are long: 25 MB to 9.5, brotli
# 2.6 MB to 2.1), else as built
es=$(ls -d "$EMBER"/node_modules/.pnpm/esbuild@*/node_modules/esbuild/bin/esbuild 2>/dev/null | tail -1)
if [ -n "$es" ]; then
  "$es" --minify "$MBUI_APP_MOD/out/web/demo.js" --outfile="$out/app.js" --log-level=error
else
  echo "web-app: no esbuild in $EMBER/node_modules (pnpm install there): the app as built, not minified" >&2
  cp "$MBUI_APP_MOD/out/web/demo.js" "$out/app.js"
fi
cp "$MBUI_DIR/web/host.js" "$out/host.js"
ls -la "$out"
gzip -9 -c "$out/app.js" | wc -c | xargs echo "app.js gzip bytes:"
