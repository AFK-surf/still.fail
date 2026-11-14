#!/bin/sh
# Builds the base for JavaScript: js/base.js and its types (js/base.d.ts, js/moonbit.d.ts), of the package src/js and
# what it reaches. Committed, as the rules' are (rules/build.sh): the core in TypeScript takes it as it is
# (client/core-ts/src/sse.ts), with no MoonBit to build it. A change to src/ runs this and commits what it made; never
# edited by hand. By the package, never the workspace: mbui is a member of it (AGENTS.md, Working here).
#   sh libs/base/build.sh           builds js/
#   sh libs/base/build.sh --check   fails where js/ is not what src/ builds to (scripts/check.sh), writing nothing there
# MBUI_TOOLS, as apps/mbui's scripts have it, says where moon is.
set -e
cd "$(dirname "$0")"
[ -n "$MBUI_TOOLS" ] && export MOON_HOME=$MBUI_TOOLS/moon PATH=$MBUI_TOOLS/moon/bin:$PATH
moon build --quiet --target js --release src/js > /dev/null
built=_build/js/release/build/base/js
[ -f $built/js.js ] && [ -f $built/js.d.ts ] && [ -f $built/moonbit.d.ts ] || { echo "base: no js.js built with its types" >&2; exit 1; }
to=js
[ "$1" != --check ] || to=$(mktemp -d)
mkdir -p $to
said="// Built by libs/base/build.sh from libs/base/src (MoonBit): not to be edited, built again."
{ echo "$said"; cat $built/js.js; } > $to/base.js
{ echo "$said"; cat $built/js.d.ts; } > $to/base.d.ts
{ echo "$said"; cat $built/moonbit.d.ts; } > $to/moonbit.d.ts
if [ "$1" = --check ]; then
  same=1
  for f in base.js base.d.ts moonbit.d.ts; do cmp -s $to/$f js/$f || { echo "libs/base/js/$f is not what libs/base/src builds to: run libs/base/build.sh and commit it" >&2; same=0; }; done
  [ "$(ls js | sort | tr '\n' ' ')" = "base.d.ts base.js moonbit.d.ts " ] || { echo "libs/base/js holds what libs/base/build.sh does not build" >&2; same=0; }
  rm -rf $to
  [ $same = 1 ]
fi
