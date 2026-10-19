#!/bin/bash
# Type-check every target of this module (and mbui with it); print errors only.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
for t in ${TARGETS:-js native}; do
  echo "=== $t"
  moon check --target $t --output-json 2>&1 | python3 "$MBUI_DIR/scripts/errs.py"
done
