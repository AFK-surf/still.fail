#!/bin/bash
# Build the browser version (APP=demo|photos): scripts/web.sh build | bundle [OUT] | test
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
# MBUI_APP_MOD: an app of a module outside this repository (its moon.work naming mbui; scripts/android.sh says more)
ROOT=$(cd "$D/.." && pwd)
CALLER_PWD=$PWD
cd "${MBUI_APP_MOD:-$ROOT}"
OUT=out/web
APP=${APP:-demo}
[ -z "${MBUI_WEB_HOOK:-}" ] || . "$MBUI_WEB_HOOK"
case "${1:-build}" in
  build)
    T0=$(python3 -c 'import time;print(time.time())')
    moon build --target js --release src/$APP 2>&1 | "$D/chk" errs
    mkdir -p $OUT
    cp $(pkg_build $APP js release)/$APP.js $OUT/demo.js
    if [ $APP = photos ]; then
      # the made-up pictures (scripts/test_images.swift --gallery)
      gallery_pictures
      mkdir -p $OUT/photos
      cp -p out/pictures/*.jpg $OUT/photos/
    fi
    cp $ROOT/web/index.html $ROOT/web/host.js $OUT/
    T1=$(python3 -c 'import time;print(time.time())')
    echo "built in $(python3 -c "print(round($T1-$T0,2))") s"
    ls -la $OUT
    gzip -9 -c $OUT/demo.js | wc -c | xargs echo "demo.js gzip bytes:"
    ;;
  bundle)
    bash "$D/web.sh" build >/dev/null
    if [ -n "${2:-}" ]; then
      DST=$(cd "$CALLER_PWD" && mkdir -p "$2" && cd "$2" && pwd)
    else
      DST=$(mkdir -p "$OUT" && cd "$OUT" && pwd)
    fi
    # minified (MoonBit's names are long) by esbuild, the version pinned here: the workspace's own where its packages
    # have it, else fetched
    ESBUILD=0.28.2
    es=$(ls -d "$PWD"/node_modules/.pnpm/esbuild@$ESBUILD/node_modules/esbuild/bin/esbuild \
      "$ROOT"/../../node_modules/.pnpm/esbuild@$ESBUILD/node_modules/esbuild/bin/esbuild \
      "$ROOT"/../../station/node_modules/.pnpm/esbuild@*/node_modules/esbuild/bin/esbuild 2>/dev/null | tail -1 || true)
    if [ -n "$es" ]; then
      "$es" --minify "$OUT/demo.js" --outfile="$DST/app.js" --log-level=error
    else
      npx --yes esbuild@$ESBUILD --minify "$OUT/demo.js" --outfile="$DST/app.js" --log-level=error
    fi
    [ "$ROOT/web/host.js" -ef "$DST/host.js" ] || cp "$ROOT/web/host.js" "$DST/host.js"
    if [ "${MBUI_WEB_BROTLI:-1}" != 0 ]; then
      for f in app.js host.js; do
        node -e 'const z = require("node:zlib"), fs = require("node:fs"), [src, dst] = process.argv.slice(1), b = fs.readFileSync(src);
fs.writeFileSync(dst, z.brotliCompressSync(b, { params: { [z.constants.BROTLI_PARAM_QUALITY]: 11,
  [z.constants.BROTLI_PARAM_LGWIN]: 24, [z.constants.BROTLI_PARAM_SIZE_HINT]: b.length } }))' "$DST/$f" "$DST/$f.br"
      done
    fi
    if type app_bundle >/dev/null 2>&1; then app_bundle "$DST"; fi
    ls -la "$DST"
    gzip -9 -c "$DST/app.js" | wc -c | xargs echo "app.js gzip bytes:"
    [ ! -f "$DST/app.js.br" ] || { wc -c < "$DST/app.js.br" | xargs echo "app.js brotli bytes (sent):"; }
    ;;
  test)
    mkdir -p out/node
    if [ ! -d out/node/node_modules/playwright ]; then
      (cd out/node && npm init -y >/dev/null && npm i playwright@latest >/dev/null 2>&1)
      (cd out/node && npx playwright install chromium >/dev/null 2>&1)
    fi
    NODE_PATH=$PWD/out/node/node_modules node scripts/web-test.mjs "${@:2}"
    ;;
esac
