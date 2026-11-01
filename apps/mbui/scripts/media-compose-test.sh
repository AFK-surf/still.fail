#!/bin/bash
# Check scene cuts, overlay timing, a delayed soundtrack, stills, and preserving output after failure.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D/.."
mkdir -p out
take=$(mktemp -d "$PWD/out/media-compose-test.XXXXXXXX")
trap 'rm -rf "$take"' EXIT
ffmpeg -v error -y -f lavfi -i 'color=c=red:s=64x64:r=30' -frames:v 12 -c:v libx264 -pix_fmt yuv420p "$take/red.mp4"
ffmpeg -v error -y -f lavfi -i 'color=c=blue:s=64x64:r=1' -frames:v 1 -threads 1 -update 1 "$take/blue.png"
ffmpeg -v error -y -f lavfi -i 'color=c=black@0.0:s=32x32:r=1,format=rgba,drawbox=x=0:y=0:w=16:h=16:color=lime:t=fill:replace=1' \
  -frames:v 1 -threads 1 -update 1 "$take/overlay.png"
ffmpeg -v error -y -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 1 "$take/tone.wav"
cat > "$take/timeline.json" <<'EOF'
{
  "width": 64, "height": 64, "fps": 30,
  "scenes": [
    {"kind": "film", "path": "red.mp4", "frames": 10},
    {"kind": "picture", "path": "blue.png", "frames": 10}
  ],
  "overlays": [{"path": "overlay.png", "at": 4, "until": 8, "x": 0, "y": 0}],
  "audio": [{"path": "tone.wav", "at": 5, "gain": 0.5}]
}
EOF
node scripts/media-compose.mjs still "$take/timeline.json" 5 "$take/still.png"
node scripts/media-compose.mjs film "$take/timeline.json" "$take/film.mp4"
ffprobe -v error -show_entries stream=codec_type,width,height,r_frame_rate,nb_frames -of json "$take/film.mp4" > "$take/probe.json"
jq -e '.streams | any(.codec_type == "audio") and any(.codec_type == "video" and .width == 64 and .height == 64 and .r_frame_rate == "30/1" and .nb_frames == "20")' "$take/probe.json" >/dev/null
pixel() {
  ffmpeg -v error -i "$1" -vf "select='eq(n,$2)',format=rgb24,crop=1:1:$3:$4" -fps_mode passthrough \
    -frames:v 1 -f rawvideo -pix_fmt rgb24 - | od -An -tu1 | awk 'NF >= 3 { print $1, $2, $3; exit }'
}
red() { set -- $1; [ "$1" -gt 200 ] && [ "$2" -lt 40 ] && [ "$3" -lt 40 ]; }
green() { set -- $1; [ "$1" -lt 40 ] && [ "$2" -gt 200 ] && [ "$3" -lt 40 ]; }
blue() { set -- $1; [ "$1" -lt 40 ] && [ "$2" -lt 40 ] && [ "$3" -gt 200 ]; }
red "$(pixel "$take/film.mp4" 3 5 5)"
green "$(pixel "$take/film.mp4" 5 5 5)"
red "$(pixel "$take/film.mp4" 8 5 5)"
blue "$(pixel "$take/film.mp4" 10 5 5)"
green "$(pixel "$take/still.png" 0 5 5)"
red "$(pixel "$take/still.png" 0 25 25)"
ffmpeg -v error -y -i "$take/film.mp4" -map 0:a:0 -ac 1 -ar 48000 -c:a pcm_s16le "$take/decoded.wav"
python3 - "$take/decoded.wav" <<'PY'
import array, math, sys, wave
with wave.open(sys.argv[1]) as f:
    samples = array.array('h', f.readframes(f.getnframes()))
def rms(a, b):
    part = samples[int(a * 48000):int(b * 48000)]
    return math.sqrt(sum(x * x for x in part) / len(part))
assert rms(0.01, 0.08) < 300, 'audio started before its frame'
assert rms(0.25, 0.35) > 500, 'audio did not start on the timeline'
PY
cp "$take/film.mp4" "$take/previous.mp4"
cp "$take/film.mp4.timeline.json" "$take/previous.json"
jq '.scenes[0].frames = 100' "$take/timeline.json" > "$take/short.json"
if node scripts/media-compose.mjs film "$take/short.json" "$take/film.mp4"; then
  echo 'media-compose-test: a short source film succeeded' >&2
  exit 1
fi
cmp "$take/film.mp4" "$take/previous.mp4"
cmp "$take/film.mp4.timeline.json" "$take/previous.json"
echo 'media-compose-test: scenes, overlays, stills, audio and failure preservation passed'
