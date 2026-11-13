#!/bin/bash
# Type-check every target; print errors only. First the determinism lint (tools/detlint): its
# report, and a failure stops here; then the hosts' H.264 conversion (scripts/avc_test.c) and log files
# (scripts/log_files_test.c).
D="$(cd "$(dirname "$0")" && pwd)"
"$D/detlint" || exit 1
# the H.264 conversion the hosts share (src/host/avc.h), as still.fail's Android AvcTest tests it
mkdir -p "$D/../out"
cc -Wall -I "$D/../src/host" "$D/avc_test.c" -o "$D/../out/avc_test" && "$D/../out/avc_test" || exit 1
# what a host's log files may keep, the queue before them, which files (src/host/log_files.h)
cc -Wall -I "$D/../src/host" "$D/log_files_test.c" -o "$D/../out/log_files_test" && "$D/../out/log_files_test" || exit 1
. "$D/env.sh"
if [ "$(uname)" = Darwin ]; then
  cc -Wall -fobjc-arc -I "$D/../src/host" -I "$MOON_HOME/include" "$D/apple_render_test.m" \
    -framework Foundation -framework QuartzCore -framework Metal -framework CoreGraphics -framework ImageIO \
    -o "$D/../out/apple_render_test" && "$D/../out/apple_render_test" || exit 1
  cc -Wall -Werror -fobjc-arc -I "$D/../src/host" "$D/ios_ime_test.m" \
    -framework Foundation -framework CoreGraphics -o "$D/../out/ios_ime_test" && "$D/../out/ios_ime_test" || exit 1
fi
for t in ${TARGETS:-native}; do
  echo "=== $t"
  moon check --target $t --output-json 2>&1 | "$D/chk" errs
done
