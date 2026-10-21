#!/bin/bash
# Type-check every target of this module (and mbui with it); print errors only. First the determinism lint (the pinned
# mbui's scripts/detlint.py, its docs/detlint.md, with apps/mbui/detlint.json: every global put back by its package's
# reset is its `globals` rule; still.fail's scripts/check.sh runs it too): its report, and a failure stops here.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
python3 "$MBUI_DIR/scripts/detlint.py" "$A" || exit 1
# the web's files the app carries, as they are now (scripts/webassets.py)
python3 "$D/webassets.py" --check || exit 1
# the fonts the app carries, as the Android app's are (scripts/fontassets.py)
python3 "$D/fontassets.py" --check || exit 1
cd "$A"
for t in ${TARGETS:-js native}; do
  echo "=== $t"
  moon check --target $t --output-json 2>&1 | python3 "$MBUI_DIR/scripts/errs.py"
done
