#!/bin/bash
# Type-check every target; print errors only. First the determinism lint (scripts/detlint.py, docs/detlint.md): its
# report, and a failure stops here; then the hosts' H.264 conversion (scripts/avc_test.c).
D="$(cd "$(dirname "$0")" && pwd)"
python3 "$D/detlint_test.py" 2> /dev/null || { python3 "$D/detlint_test.py"; exit 1; }
python3 "$D/detlint.py" || exit 1
# the H.264 conversion the hosts share (src/host/avc.h), as still.fail's Android AvcTest tests it
mkdir -p "$D/../out"
cc -Wall -I "$D/../src/host" "$D/avc_test.c" -o "$D/../out/avc_test" && "$D/../out/avc_test" || exit 1
. "$D/env.sh"
for t in ${TARGETS:-js native}; do
  echo "=== $t"
  moon check --target $t --output-json 2>&1 | python3 "$D/errs.py"
done
