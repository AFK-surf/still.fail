#!/bin/bash
# Build the browser version (APP=demo|photos): scripts/web.sh build | test
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
OUT=out/web
APP=${APP:-demo}
case "${1:-build}" in
  build)
    T0=$(python3 -c 'import time;print(time.time())')
    moon build --target js --release src/$APP 2>&1 | python3 "$D/errs.py"
    mkdir -p $OUT
    cp _build/js/release/build/$APP/$APP.js $OUT/demo.js
    if [ $APP = photos ] && [ ! -f $OUT/photos/11.jpg ]; then
      # JPEGs from macOS's desktop picture thumbnails
      mkdir -p $OUT/photos
      i=0
      for f in "/System/Library/Desktop Pictures/.thumbnails/"*.heic; do
        [ $i -lt 12 ] || break
        sips -s format jpeg "$f" --out $OUT/photos/$i.jpg >/dev/null && i=$((i + 1))
      done
    fi
    cp web/index.html web/host.js $OUT/
    T1=$(python3 -c 'import time;print(time.time())')
    echo "built in $(python3 -c "print(round($T1-$T0,2))") s"
    ls -la $OUT
    gzip -9 -c $OUT/demo.js | wc -c | xargs echo "demo.js gzip bytes:"
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
