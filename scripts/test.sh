#!/bin/bash
# UI tests against the fake host (no window). UPDATE=1 refreshes snapshots.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
moon test --target js -p mbui/ui ${UPDATE:+--update} 2>&1 | grep -v '^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │' | tail -${LINES_OUT:-60}
