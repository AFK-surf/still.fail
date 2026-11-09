#!/bin/bash
# The native views' self-test on macOS, without MoonBit: selftest.m drives
# src/host/apple_views.m (video read through the read API, a web page),
# apple_image.m's PDFs and apple_render.m's snapshots with holes, as the app
# would. Makes its own media (ffmpeg, make_pdf.py):
#   test/apple_views/run.sh [out dir]      (prints SELFTEST PASS or FAIL lines)
set -e
D="$(cd "$(dirname "$0")" && pwd)"
R="$(cd "$D/../.." && pwd)"
. "$R/scripts/env.sh"
node --test "$D/web-video.test.mjs"
OUT=${1:-$R/out/views-test}
rm -rf "$OUT"; mkdir -p "$OUT"
# a big file (some 18 MB: many reads, cut at 4 MB, answered 1 MB at a time) with its index at the end, and a
# small one with it first
ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=1280x720:rate=30 -f lavfi -i sine=frequency=440 -t 12 \
  -vf noise=alls=30:allf=t -c:v libx264 -preset ultrafast -b:v 12M -maxrate 12M -bufsize 24M -pix_fmt yuv420p \
  -c:a aac -shortest "$OUT/test.mp4"
ffmpeg -loglevel error -y -f lavfi -i testsrc=size=320x240:rate=30 -t 5 \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$OUT/test.mov"
ffmpeg -loglevel error -y -f lavfi -i testsrc=size=320x240:rate=10 -t 5 \
  -c:v libx264 -pix_fmt yuv420p "$OUT/test.3gp"
ffmpeg -loglevel error -y -f lavfi -i testsrc=size=320x240:rate=10 -t 5 \
  -c:v libx264 -pix_fmt yuv420p "$OUT/test.3g2"
ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=320x240:rate=10 -t 5 -c:v libvpx-vp9 "$OUT/test-vp9.webm"
ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=320x240:rate=10 -t 5 -c:v libvpx "$OUT/test-vp8.webm"
ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=320x240:rate=10 -f lavfi -i sine=frequency=440:sample_rate=48000 \
  -t 5 -c:v libvpx-vp9 -c:a libopus -shortest "$OUT/test-vp9-opus.webm"
ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=320x240:rate=10 -f lavfi -i sine=frequency=440:sample_rate=48000 \
  -t 5 -vf "drawbox=x=120:y=80:w=80:h=80:color=red:t=fill:enable='lt(t,2)',drawbox=x=120:y=80:w=80:h=80:color=blue:t=fill:enable='gte(t,2)'" \
  -c:v libvpx-vp9 -c:a aac -shortest "$OUT/test-vp9-aac.mp4"
ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=320x240:rate=10 -t 5 \
  -c:v libx265 -preset ultrafast -x265-params log-level=error:pools=1 -tag:v hvc1 "$OUT/test-hevc.mp4"
ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=320x240:rate=10 -t 5 \
  -c:v libx265 -preset ultrafast -x265-params log-level=error:pools=1 -tag:v hev1 "$OUT/test-hev1.mp4"
ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=640x360:rate=30 -t 12 -vf noise=alls=45:allf=t \
  -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 8M "$OUT/test-large.webm"
cp "$R/test/host/playcheck-vp9-profile1.webm" "$OUT/profile1.webm"
cp "$R/test/host/playcheck-theora.ogv" "$OUT/test-theora.ogv"
cp "$R/test/host/playcheck-av1.webm" "$OUT/test-av1.webm"
cp "$R/test/host/playcheck-av1-10bit.webm" "$OUT/test-av1-10bit.webm"
cp "$R/test/host/playcheck-av1.mp4" "$OUT/test-av1.mp4"
head -c 4096 /dev/zero > "$OUT/damaged.mp4"
python3 "$D/make_pdf.py" "$OUT/test.pdf"
RT=""
for f in runtime; do RT="$RT $MOON_HOME/lib/runtime/$f.c"; done
clang -fobjc-arc -O1 -Wall -Wno-unused-function -I"$MOON_HOME/include" -I"$R/src/host" \
  -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_SYSTEM -DMBUI_HOST_SELFTEST -fwrapv -fno-strict-aliasing \
  "$D/selftest.m" "$R/src/host/apple_views.m" "$R/src/host/apple_image.m" "$R/src/host/apple_render.m" \
  "$R/src/host/apple_text.m" $RT \
  -framework Cocoa -framework Metal -framework QuartzCore -framework CoreText -framework CoreGraphics \
  -framework ImageIO -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework WebKit \
  -o "$OUT/selftest"
"$OUT/selftest" "$OUT" "$OUT/test.pdf" "$OUT/test.mp4|video/mp4|12000|1280|720" \
  "$OUT/test.mov|video/quicktime|5000|320|240" "$OUT/test.3gp|video/3gpp|5000|320|240" \
  "$OUT/test.3g2|video/3gpp2|5000|320|240" "$OUT/test-hevc.mp4|video/mp4|5000|320|240" 2>&1 | tee "$OUT/log.txt"
grep -q "SELFTEST PASS" "$OUT/log.txt"
