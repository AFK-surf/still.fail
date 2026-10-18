#!/bin/bash
# Type-check every target; print errors only.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
for t in ${TARGETS:-js native}; do
  echo "=== $t"
  moon check --target $t --output-json 2>&1 | python3 "$D/errs.py"
done
