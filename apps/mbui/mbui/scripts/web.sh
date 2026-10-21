#!/bin/bash
# Build the browser version (APP=demo|photos): scripts/web.sh build | test
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
# MBUI_APP_MOD: an app of a module outside this repository (its moon.work naming mbui; scripts/android.sh says more)
ROOT=$(cd "$D/.." && pwd)
cd "${MBUI_APP_MOD:-$ROOT}"
OUT=out/web
APP=${APP:-demo}
case "${1:-build}" in
  build)
    T0=$(python3 -c 'import time;print(time.time())')
    moon build --target js --release src/$APP 2>&1 | python3 "$D/errs.py"
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
  test)
    mkdir -p out/node
    if [ ! -d out/node/node_modules/playwright ]; then
      (cd out/node && npm init -y >/dev/null && npm i playwright@latest >/dev/null 2>&1)
      (cd out/node && npx playwright install chromium >/dev/null 2>&1)
    fi
    NODE_PATH=$PWD/out/node/node_modules node scripts/web-test.mjs "${@:2}"
    ;;
esac
