#!/bin/bash
set -o pipefail
R=$(pwd)
(cd station && npx -y pnpm@10.33.0 install --frozen-lockfile) > ../install.log 2>&1 || { tail -20 ../install.log; exit 1; }
(cd client/core-ts && npx -y pnpm@10.33.0 install --frozen-lockfile) >> ../install.log 2>&1 || { tail -20 ../install.log; exit 1; }
echo "=== shapes"; node client/core-ts/scripts/shapes.ts 2>&1 | tail -5
echo "=== strings"; bash apps/mbui/scripts/strings "$R" 2>&1 | tail -5
echo "=== station test"; (cd station && node --test --test-force-exit --test-reporter=tap test/share.test.ts test/platform.test.ts > ../t-st.txt 2>&1); grep -E "^# (pass|fail)|^not ok" t-st.txt; grep -B2 -A25 "^not ok" t-st.txt | grep -v "^ *at " | head -60
echo "=== station tsgo"; (cd station && npx tsgo -p tsconfig.json --noEmit 2>&1 | head)
echo "=== core tsgo"; (cd client/core-ts && npx tsgo --noEmit 2>&1 | head)
echo "=== mbui check"; (. apps/mbui/scripts/env.sh && cd apps/mbui && moon check --target native 2>&1 | grep -v "^Warning\|^ *$" | tail -20)
