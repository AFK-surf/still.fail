#!/bin/bash
# still.fail's app in a browser, on the web's own core (web/mbui.html, web/src/mbui/core.ts): the app built for the
# browser (scripts/web.sh, APP=stillfail) and mbui's web host put where the web's build serves them, web/public/mbui
# (ignored); `pnpm run build:cloud` then makes it every page of the web app's (web/vite.config.ts), `pnpm dev:web` serves it
# at /mbui.html.
#   scripts/web-app.sh
set -e
D="$(cd "$(dirname "$0")" && pwd)"
APP=stillfail bash "$D/web.sh" build >/dev/null
. "$D/env.sh"
out=$EMBER/web/public/mbui
mkdir -p "$out"
# minified (MoonBit's names are long: 25 MB to 9.5, brotli 4.3 MB to 2.1) by esbuild, the version pinned here: the
# web's own where its packages have it, else fetched (CI's mbui-web, whose install has none: deployed unminified once)
ESBUILD=0.28.2
es=$(ls -d "$EMBER"/node_modules/.pnpm/esbuild@$ESBUILD/node_modules/esbuild/bin/esbuild 2>/dev/null | tail -1)
if [ -n "$es" ]; then
  "$es" --minify "$MBUI_APP_MOD/out/web/demo.js" --outfile="$out/app.js" --log-level=error
else
  npx --yes esbuild@$ESBUILD --minify "$MBUI_APP_MOD/out/web/demo.js" --outfile="$out/app.js" --log-level=error
fi
cp "$MBUI_DIR/web/host.js" "$out/host.js"
# the files the app carries, fetched beside its script (tools/assets; the page's src/mbui/core.ts)
rm -rf "$out/assets"
bash "$D/assets" "$MBUI_APP_MOD" "$out/assets" > /dev/null
ls -la "$out"
gzip -9 -c "$out/app.js" | wc -c | xargs echo "app.js gzip bytes:"
