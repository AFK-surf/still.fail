#!/bin/bash
# Check the native core's build cache, then type-check every target of this module (and mbui with it). The determinism
# lint (mbui's tools/detlint, with apps/mbui/detlint.json) reports errors before type-checking.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
node --test "$D/waitfor.test.mjs" "$D/recording-privacy.test.mjs" "$D/rerecord.test.mjs" "$D/toolchain-env.test.mjs" "$D/e2e-local-cleanup.test.mjs" || exit 1
# A warm native build must use the current checkout's core, including when several release runners share its outputs.
bash "$D/core-cache-test.sh" || exit 1
# what the desktops hand this machine's station's installer (src/host/station_install.h)
mkdir -p "$A/out"
cc -Wall -I "$A/src/host" -I "$MBUI_DIR/src/host" "$D/station_install_test.c" -o "$A/out/station_install_test" && "$A/out/station_install_test" || exit 1
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
