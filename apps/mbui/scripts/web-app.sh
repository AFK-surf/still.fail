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
out=$SF_SRC/web/public/mbui
mkdir -p "$out"
# minified (MoonBit's names are long: 25 MB to 9.5, brotli 4.3 MB to 2.1) by esbuild, the version pinned here: the
# web's own where its packages have it, else fetched (CI's mbui-web, whose install has none: deployed unminified once)
ESBUILD=0.28.2
es=$(ls -d "$SF_SRC"/node_modules/.pnpm/esbuild@$ESBUILD/node_modules/esbuild/bin/esbuild 2>/dev/null | tail -1)
if [ -n "$es" ]; then
  "$es" --minify "$MBUI_APP_MOD/out/web/demo.js" --outfile="$out/app.js" --log-level=error
else
  npx --yes esbuild@$ESBUILD --minify "$MBUI_APP_MOD/out/web/demo.js" --outfile="$out/app.js" --log-level=error
fi
cp "$MBUI_DIR/web/host.js" "$out/host.js"
# each script brotlied at the highest level beside it, what the web's Worker sends a browser that takes brotli
# (cloud/src/web.ts packed): Cloudflare's own on the fly is a lower level's, app.js 2.26 MB against 1.66 (2026-11-09)
for f in app.js host.js; do
  node -e 'const z = require("node:zlib"), fs = require("node:fs"), [src, dst] = process.argv.slice(1), b = fs.readFileSync(src);
fs.writeFileSync(dst, z.brotliCompressSync(b, { params: { [z.constants.BROTLI_PARAM_QUALITY]: 11,
  [z.constants.BROTLI_PARAM_LGWIN]: 24, [z.constants.BROTLI_PARAM_SIZE_HINT]: b.length } }))' "$out/$f" "$out/$f.br"
done
# the files the app carries, fetched beside its script (tools/assets; the page's src/mbui/core.ts)
rm -rf "$out/assets"
bash "$D/assets" "$MBUI_APP_MOD" "$out/assets" > /dev/null
ls -la "$out"
gzip -9 -c "$out/app.js" | wc -c | xargs echo "app.js gzip bytes:"
wc -c < "$out/app.js.br" | xargs echo "app.js brotli bytes (sent):"
