#!/bin/bash
# Yoga conformance for src/flex: pass count per Yoga file and the first failures.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
moon test --target js -p mbui/flex 2>&1 | grep -v '^Warning' > out/flextest.log
python3 - <<'PY'
import re, collections
log = open("out/flextest.log").read()
fails = re.findall(r"test flex/(yoga_\w+)_test\.mbt:\d+ \(\"([^\"]+)\"\) failed: .*?FAILED: (.*)", log)
tot = re.search(r"Total tests: (\d+), passed: (\d+), failed: (\d+)", log)
print(tot.group(0) if tot else log[-3000:])
by = collections.Counter(f[0] for f in fails)
for k, v in sorted(by.items(), key=lambda x: -x[1]):
    print(f"  {k}: {v} failing")
skip = __import__('os').environ.get('SKIP', '')
for f in [f for f in fails if not skip or skip not in f[0]][:int(__import__('os').environ.get('SHOW', '25'))]:
    print(f"- {f[1]}: {f[2][:160]}")
PY
