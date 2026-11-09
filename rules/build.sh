#!/bin/sh
# Builds the rules for JS (rules/js/rules.js, committed: station, cloud and the core take it as it is, with no MoonBit
# to build it). MBUI_TOOLS, as apps/mbui's scripts have it, says where moon is.
set -e
cd "$(dirname "$0")"
[ -n "$MBUI_TOOLS" ] && export MOON_HOME=$MBUI_TOOLS/moon PATH=$MBUI_TOOLS/moon/bin:$PATH
moon build --target js --release
built=$(find _build/js/release -name 'js.js' -path '*/js/*' | head -1)
[ -n "$built" ] || { echo "rules: no js.js built" >&2; exit 1; }
mkdir -p js
# MoonBit's maps draw their hash seed when the module loads; a Cloudflare worker (cloud/, which takes the lock through
# station/src/cloud/lock.ts) may not draw random values before a request. Drawn the first time a map wants it instead.
node -e '
const fs = require("fs");
const [from, to] = process.argv.slice(1);
let js = fs.readFileSync(from, "utf8");
const at = "const _M0FPB4seed = _M0FPB12random__seed();";
if (js.split(at).length !== 2) { console.error("rules: the hash seed is not drawn as it was; see rules/build.sh"); process.exit(1); }
js = js.replace(at, "let _M0FPB4seed__held;\nconst _M0FPB4seed__drawn = () => (_M0FPB4seed__held === undefined ? (_M0FPB4seed__held = _M0FPB12random__seed()) : _M0FPB4seed__held);");
js = js.replace(/\b_M0FPB4seed\b(?!_)/g, "_M0FPB4seed__drawn()");
fs.writeFileSync(to, "// Built by rules/build.sh from rules/src (MoonBit): not to be edited, built again.\n" + js);
' "$built" js/rules.js
