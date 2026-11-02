#!/bin/bash
# Check the native core's build cache, then type-check every target of this module (and mbui with it). The determinism
# lint (mbui's tools/detlint, docs/detlint.md, with apps/mbui/detlint.json) reports errors before type-checking.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
# A warm native build must use the current checkout's core, including when several release runners share its outputs.
bash "$D/core-cache-test.sh" || exit 1
"$MBUI_DIR/scripts/detlint" "$A" || exit 1
# the web's files the app carries, as they are now (scripts/webassets.py)
python3 "$D/webassets.py" --check || exit 1
# the fonts the app carries, as the Android app's are (scripts/fontassets.py)
python3 "$D/fontassets.py" --check || exit 1
# every catalog key the sources say listed in its package's words.txt (scripts/words.py)
python3 "$D/words.py" --check || exit 1
cd "$A"
for t in ${TARGETS:-native}; do
  echo "=== $t"
  moon check --target $t --output-json 2>&1 | "$MBUI_DIR/scripts/chk" errs
done
