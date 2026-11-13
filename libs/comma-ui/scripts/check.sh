#!/bin/bash
# Comma's parts' module on its own (mbui beside it, ../mbui): the determinism lint with this module's detlint.json, its
# packages type-checked on native, then its tests (CI's check-comma-ui; here as well, they take seconds).
D="$(cd "$(dirname "$0")" && pwd)"
A=$(cd "$D/.." && pwd)
MBUI_DIR=$(cd "$A/../mbui" && pwd)
. "$MBUI_DIR/scripts/env.sh"
"$MBUI_DIR/scripts/detlint" "$A" || exit 1
cd "$A"
moon check --target native --output-json 2>&1 | "$MBUI_DIR/scripts/chk" errs
[ "${PIPESTATUS[0]}" = 0 ] || exit 1
moon test --target native --release -p comma-ui/cm 2>&1 | tail -${LINES_OUT:-40}
exit "${PIPESTATUS[0]}"
