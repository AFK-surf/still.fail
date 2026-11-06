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
pairs="typing-before:typing-after caret-before:caret-hidden caret-hidden:caret-shown
regions-before:regions-moved regions-moved:regions-shrunk regions-shrunk:regions-gone regions-gone:regions-new
clips-before:clips-after glass-before:glass-after"
# A missing frame this run must not be supplied by an earlier run in this directory. Only these generated files
# belong to this check; keep anything else the caller stored beside them.
for pair in $pairs; do
  for name in "${pair%:*}" "${pair#*:}"; do
    rm -f "$O/$name.dl" "$O/$name.png" "$O/$name.whole.png" "$O/$name.render.log"
  done
done
renderer=${MBUI_PAINT_DAMAGE_RENDERER:-}
if [ -z "$renderer" ]; then
  (unset MBUI_APP_MOD; APP=render bash "$D/mac.sh" build) > "$O/build.log" 2>&1
  renderer="$PWD/$(pkg_build render native release)/render.exe"
fi
code=0
# The producer has no host: first use its fixed text to request the same words from this renderer. Cluster numbers
# and boxes from one font system cannot name glyphs in another. Then run the same inputs with this host's replies.
# Both runs use the Wasm test program; no second native UI test build is needed in the rendering job.
MBUI_PAINT_DAMAGE_PRINT=1 MBUI_PAINT_DAMAGE_TEXT= moon test --target wasm-gc --release src/ui/field_present_wbtest.mbt > "$O/seed.log" 2>&1 || code=1
MBUI_DL_RECORD_TEXT=1 MBUI_DL="$O/seed.log" "$renderer" > "$O/text.log" 2>&1 || {
  echo "paint damage: host text recording failed (see $O/text.log)"
  exit 1
}
if ! grep -q 'mbui-render: text recorded' "$O/text.log"; then
  echo "paint damage: host text recording did not finish (see $O/text.log)"
  exit 1
fi
sed -n 's/^.*TEXTREC /TEXTREC /p' "$O/text.log" > "$O/host.textrec"
if [ ! -s "$O/host.textrec" ]; then
  echo "paint damage: host text recording is empty (see $O/text.log)"
  exit 1
fi
MBUI_PAINT_DAMAGE_PRINT=1 MBUI_PAINT_DAMAGE_TEXT="$(cat "$O/host.textrec")" \
  moon test --target wasm-gc --release src/ui/field_present_wbtest.mbt > "$O/frames.log" 2>&1 || code=1
awk -v out="$O" '/^DLEND/{p=0; close(file)} p{print > file} /^DLBEGIN /{file=out "/" $2 ".dl"; p=1}' "$O/frames.log"
for pair in $pairs; do
  before=${pair%:*}
  after=${pair#*:}
  if [ ! -s "$O/$before.dl" ] || [ ! -s "$O/$after.dl" ]; then
    echo "paint damage: missing draw list $pair (see $O/frames.log)"
    code=1
    continue
  fi
  MBUI_DL_FROM="$O/$before.dl" MBUI_DL="$O/$after.dl" MBUI_DL_PNG="$O/$after.png" \
    "$renderer" > "$O/$after.render.log" 2>&1 || {
      echo "paint damage: $after renderer failed (see $O/$after.render.log)"
      code=1
      continue
    }
  if grep -Eq '[1-9][0-9]* (not known here|another size here)' "$O/$after.render.log"; then
    echo "paint damage: $after has glyphs that do not match the host's text (see $O/$after.render.log)"
    code=1
  elif [ ! -s "$O/$after.png" ] || [ ! -s "$O/$after.whole.png" ]; then
    echo "paint damage: $after did not produce both pictures (see $O/$after.render.log)"
    code=1
  elif cmp -s "$O/$after.png" "$O/$after.whole.png"; then
    echo "paint damage: $after partial and whole match"
  else
    echo "paint damage: $after partial and whole differ"
    code=1
  fi
done
exit "$code"
