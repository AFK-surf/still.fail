#!/bin/bash
# Paint-only changes handed to the real host: render the preceding draw list whole, this one in exactly the parts
# h_present sent, and this one whole. Every pair must have identical pixels (docs/partial-redraw.md).
# MBUI_PAINT_DAMAGE_RENDERER may name an already built renderer of these sources; otherwise build the macOS host.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
O=${1:-out/paint-damage}
mkdir -p "$O"
O=$(cd "$O" && pwd)
code=0
MBUI_PAINT_DAMAGE_PRINT=1 moon_tests src/ui/field_present_wbtest.mbt > "$O/frames.log" 2>&1 || code=1
awk -v out="$O" '/^DLEND/{p=0; close(file)} p{print > file} /^DLBEGIN /{file=out "/" $2 ".dl"; p=1}' "$O/frames.log"
renderer=${MBUI_PAINT_DAMAGE_RENDERER:-}
if [ -z "$renderer" ]; then
  (unset MBUI_APP_MOD; APP=render bash "$D/mac.sh" build) > "$O/build.log" 2>&1
  renderer="$PWD/$(pkg_build render native release)/render.exe"
fi
for pair in typing-before:typing-after caret-before:caret-hidden caret-hidden:caret-shown \
  regions-before:regions-moved regions-moved:regions-shrunk regions-shrunk:regions-gone regions-gone:regions-new \
  clips-before:clips-after glass-before:glass-after; do
  before=${pair%:*}
  after=${pair#*:}
  if [ ! -s "$O/$before.dl" ] || [ ! -s "$O/$after.dl" ]; then
    echo "paint damage: missing draw list $pair (see $O/frames.log)"
    code=1
    continue
  fi
  MBUI_DL_FROM="$O/$before.dl" MBUI_DL="$O/$after.dl" MBUI_DL_PNG="$O/$after.png" \
    "$renderer" > "$O/$after.render.log" 2>&1
  if cmp -s "$O/$after.png" "$O/$after.whole.png"; then
    echo "paint damage: $after partial and whole match"
  else
    echo "paint damage: $after partial and whole differ"
    code=1
  fi
done
exit "$code"
