#!/bin/bash
# still.fail's app in a browser, on the web's own core (web/mbui.html, web/src/mbui/core.ts): the app built and bundled
# for the browser (mbui's scripts/web.sh bundle, APP=stillfail) and the files it carries put where the web's build
# serves them, web/public/mbui (ignored); `pnpm run build:cloud` then makes it every page of the web app's
# (web/vite.config.ts), `pnpm dev:web` serves it at /mbui.html.
#   scripts/web-app.sh
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
out=$SF_SRC/web/public/mbui
rm -rf "$out/assets"
mkdir -p "$out"
bash "$D/assets" "$MBUI_APP_MOD" "$out/assets" > /dev/null
APP=stillfail exec bash "$MBUI_DIR/scripts/web.sh" bundle "$out"
