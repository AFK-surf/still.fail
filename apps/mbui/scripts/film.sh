#!/bin/bash
# A scripted run of still.fail filmed offscreen, straight into a video (src/sffilm: mbui's film, mbui/src/film): the app
# over its made-up chats (MBUI_FIXTURE, chat by default; MBUI_DARK=1 the dark theme) in a phone's window (MBUI_WIN,
# 390x844), run in a Tester of this Mac's text and pictures, every frame drawn by the Mac's renderer with no window
# and written into the film at its moment, 60 a second. No screen, no real time: the same run is the same film.
#   scripts/film.sh <name> <drive script>           out/film/<name>.mp4 (scripts/motion/<drive script>.drive run), and
#                                                   <name>.mp4.textrec (the run's text: a test's to see it again)
#   scripts/film.sh side <name> <a.mp4> <b.mp4>     the two side by side, 20 apart on white: out/film/<name>.mp4
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
mkdir -p out/film
if [ "${1:-}" = side ]; then
  FF=$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)
  "$FF" -loglevel error -y -i "$3" -i "$4" -filter_complex "[0:v]pad=iw+20:ih:0:0:white[a];[a][1:v]hstack=inputs=2" \
    -c:v libx264 -pix_fmt yuv420p -crf 18 "out/film/$2.mp4" || exit 1
  echo "SIDE out/film/$2.mp4"
  exit 0
fi
name=${1:?name}
drive=${2:?drive script (scripts/motion/<it>.drive)}
[ -f "scripts/motion/$drive.drive" ] || { echo "film.sh: no scripts/motion/$drive.drive" >&2; exit 2; }
APP=sffilm MODE=release bash scripts/mac.sh build >/dev/null || exit 1
env MBUI_FIXTURE=${MBUI_FIXTURE:-chat} MBUI_WIN=${MBUI_WIN:-390x844} MBUI_FILM="$PWD/out/film/$name.mp4" \
  MBUI_FILM_DRIVE="$PWD/scripts/motion/$drive.drive" ./_build/native/release/build/stillfail/sffilm/sffilm.exe
