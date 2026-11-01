#!/bin/bash
# The native views' self-test on macOS, without MoonBit: selftest.m drives
# src/host/apple_views.m (video read through the read API, a web page),
# apple_image.m's PDFs and apple_render.m's snapshots with holes, as the app
# would. Makes its own media (ffmpeg, make_pdf.py). On Studio:
#   test/apple_views/run.sh [out dir]      (prints SELFTEST PASS or FAIL lines)
set -e
D="$(cd "$(dirname "$0")" && pwd)"
R="$(cd "$D/../.." && pwd)"
. "$R/scripts/env.sh"
OUT=${1:-$R/out/views-test}
rm -rf "$OUT"; mkdir -p "$OUT"
# a big file (some 18 MB: many reads, cut at 4 MB, answered 1 MB at a time) with its index at the end, and a
# small one with it first
ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=1280x720:rate=30 -f lavfi -i sine=frequency=440 -t 12 \
  -vf noise=alls=30:allf=t -c:v libx264 -preset ultrafast -b:v 12M -maxrate 12M -bufsize 24M -pix_fmt yuv420p \
  -c:a aac -shortest "$OUT/test.mp4"
ffmpeg -loglevel error -y -f lavfi -i testsrc=size=320x240:rate=30 -t 5 \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$OUT/test.mov"
ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=32x32:rate=1 -frames:v 1 -c:v libvpx "$OUT/test.webm"
head -c 4096 /dev/zero > "$OUT/damaged.mp4"
python3 "$D/make_pdf.py" "$OUT/test.pdf"
RT=""
for f in runtime; do RT="$RT $MOON_HOME/lib/runtime/$f.c"; done
clang -fobjc-arc -O1 -Wall -Wno-unused-function -I"$MOON_HOME/include" -I"$R/src/host" \
  -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_SYSTEM -fwrapv -fno-strict-aliasing \
  "$D/selftest.m" "$R/src/host/apple_views.m" "$R/src/host/apple_image.m" "$R/src/host/apple_render.m" \
  "$R/src/host/apple_text.m" $RT \
  -framework Cocoa -framework Metal -framework QuartzCore -framework CoreText -framework CoreGraphics \
  -framework ImageIO -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework WebKit \
  -o "$OUT/selftest"
"$OUT/selftest" "$OUT" "$OUT/test.pdf" "$OUT/test.mp4|video/mp4|12000|1280|720" \
  "$OUT/test.mov|video/quicktime|5000|320|240" 2>&1 | tee "$OUT/log.txt"
grep -q "SELFTEST PASS" "$OUT/log.txt"
