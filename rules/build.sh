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
cp "$built" js/rules.js
