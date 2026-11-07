#!/bin/bash
# The browser build of this module's apps (APP=sffix by default): mbui's scripts/web.sh build | test.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
export APP=${APP:-sffix}
bash "$MBUI_DIR/scripts/web.sh" "$@" || exit $?
if [ "${1:-build}" = build ] && { [ "$APP" = stillfail ] || [ "$APP" = sfmedia ]; }; then
  out=$A/out/web
  bash "$MBUI_DIR/native/svg/build.sh" wasm "$out/svg.wasm" || exit 1
  cp "$MBUI_DIR/native/svg/loader.mjs" "$out/svg.mjs"
  sed 's|<script src="demo.js"></script>|<script type="module">import { loadSvg } from "./svg.mjs"; globalThis.mbuiSvg = await loadSvg(await WebAssembly.compileStreaming(fetch("./svg.wasm"))); await import("./demo.js");</script>|' "$MBUI_DIR/web/index.html" > "$out/index.html"
fi
