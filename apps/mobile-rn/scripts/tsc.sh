#!/bin/bash
# Type-checks the app (on studio, through station_task with this worktree as `dir`): its packages installed the first
# time, the web build's one generated file stood in for, then tsc. Prints the errors, at most `${1:-80}` lines.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"
[ -d node_modules ] || npm install --legacy-peer-deps --silent > /dev/null 2>&1
[ -f ../../web/src/core/iroh-pkg/built.js ] || { mkdir -p ../../web/src/core/iroh-pkg; echo "export const BUILT_AT = 0;" > ../../web/src/core/iroh-pkg/built.js; echo "export declare const BUILT_AT: number;" > ../../web/src/core/iroh-pkg/built.d.ts; }
out=$(npx tsc --noEmit 2>&1); s=$?
echo "$out" | head -n "${1:-80}"
echo "tsc: $(echo "$out" | grep -c "error TS") errors"
exit $s
