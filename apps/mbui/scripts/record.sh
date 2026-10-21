#!/bin/bash
# A motion recorded frame by frame on macOS (src/host/mac_app.m MBUI_RECORD: 60 frames a second on the app's own
# clock, however long each takes to draw), as a video and the frames' motion log:
#   scripts/record.sh <name> [frames] [drive script]
# runs still.fail over its made-up chats (APP=sffix; MBUI_FIXTURE and the rest from the environment) in a phone's
# window, a scripted run of scripts/motion/<drive script>.drive if given (MBUI_DRIVE), MBUI_MOTION_LOG=1; writes
# out/rec/<name>.mp4, out/rec/<name>/log.txt (`MOTION <ms> <key> …` lines: scripts/motionplot.py) and the frames.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
name=$1
frames=${2:-300}
drive=$3
dir=out/rec/$name
rm -rf "$dir"; mkdir -p "$dir"
APP=sffix MODE=release bash scripts/mac.sh build >/dev/null || exit 1
extra=()
if [ -n "$drive" ]; then extra=(MBUI_DRIVE_B64="$(base64 < scripts/motion/$drive.drive | tr -d '\n')"); fi
env MBUI_WIN=${MBUI_WIN:-390x844} MBUI_RECORD="$PWD/$dir" MBUI_RECORD_FRAMES=$frames MBUI_MOTION_LOG=1 "${extra[@]}" \
  ./_build/native/release/build/stillfail/sffix/sffix.exe > "$dir/log.txt" 2>&1
n=$(ls "$dir"/f*.png 2>/dev/null | wc -l | tr -d ' ')
echo "RECORDED $name: $n frames"
FF=$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)
"$FF" -loglevel error -y -framerate 60 -i "$dir/f%05d.png" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -pix_fmt yuv420p -crf 20 "out/rec/$name.mp4" && echo "VIDEO out/rec/$name.mp4"
# a strip of what moved: every 3rd frame from the first moving one (with STRIP_KEY in its key), 24 of them
# (out/rec/<name>-strip.png)
from=$(python3 - "$dir/log.txt" "${STRIP_KEY:-}" <<'PY'
import re, sys
t0, first = None, None
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"RECORD t0 (\S+)", line)
    if m:
        t0 = float(m.group(1))
    m = re.match(r"MOTION (\S+) (.*)", line)
    if m and t0 is not None and first is None and sys.argv[2] in m.group(2):
        first = float(m.group(1))
print(max(0, int(round((first - t0) / (1000 / 60))) - 2) if first is not None and t0 is not None else 0)
PY
)
"$FF" -loglevel error -y -start_number $from -framerate 60 -i "$dir/f%05d.png" \
  -vf "select=not(mod(n\,3)),scale=260:-1,tile=8x3" -frames:v 1 "out/rec/$name-strip.png" && echo "STRIP out/rec/$name-strip.png (from frame $from)"

