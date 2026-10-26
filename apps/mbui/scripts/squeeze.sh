#!/bin/bash
# What is squeezed, seen: sffix's made-up screens (MBUI_FIXTURE modes) filmed offscreen in this Mac's text (src/sffilm,
# scripts/film.sh) in the narrowest windows each frame is drawn in, each one's squeeze faults said (mbui's squeeze.mbt,
# the drive step `squeeze`) and its last frame kept as a picture: out/squeeze/<size>-<lang>/<mode>.png, the faults in
# out/squeeze/faults.txt. For people looking at what does not fit; the checks are the Tester's (squeeze_wbtest.mbt).
#   scripts/squeeze.sh [MODE…]            the modes given, else those of SQUEEZE_MODES (a few dozen of each page)
#   SIZES="touch600 desk600 phone320"     which windows (touchW: a tablet's, a finger, medium in width under 840 and
#                                         expanded from there; deskW: a Mac's; phoneW)
#   LANGS="zh en"                         in which of the app's languages
#   MBUI_SAID=1                           what people, agents and stations wrote at its longest (src/sfapp/fixture_said.mbt:
#                                         the stretched pass of squeeze_said_wbtest.mbt), into out/squeeze-said
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
FF=$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)
APP=sffilm MODE=release bash scripts/mac.sh build >/dev/null || exit 1
EXE=./_build/native/release/build/stillfail/sffilm/sffilm.exe
MODES=${*:-${SQUEEZE_MODES:-home chat newchat files drive settings-home settings-station settings-profiles}}
OUT=out/squeeze; [ "${MBUI_SAID:-}" = 1 ] && OUT=out/squeeze-said
mkdir -p $OUT
: > $OUT/faults.txt
for size in ${SIZES:-touch600 desk600 phone320}; do
  w=${size//[a-z]/}
  case $size in
    touch*) h=900; platform=2; room=medium; [ "$w" -ge 840 ] && room=expanded
      system="system {\"size_class\":{\"width\":\"$room\",\"height\":\"medium\"}}" ;;
    phone*) h=700; platform=2; system='' ;;
    *) h=760; platform=0; system='' ;;
  esac
  for lang in ${LANGS:-zh en}; do
    dir="$OUT/$size-$lang"
    mkdir -p "$dir"
    for mode in $MODES; do
      script="$dir/$mode.drive"
      printf '%s\ntimeout 4000\nwait 1200\nsqueeze\nexit\n' "$system" > "$script"
      film="$dir/$mode.mp4"
      MBUI_LOCALE=$lang MBUI_FIXTURE=$mode MBUI_WIN=${w}x$h MBUI_FILM_PLATFORM=$platform MBUI_FILM_SCALE=2 \
        MBUI_FILM="$PWD/$film" MBUI_FILM_LAST="$PWD/$dir/$mode.png" MBUI_FILM_DRIVE="$PWD/$script" "$EXE" 2>&1 | grep 'DRIVE SQUEEZE' \
        | sed "s|^.*DRIVE SQUEEZE |$size-$lang $mode: |" >> $OUT/faults.txt
      # (the last frame as drawn, MBUI_FILM_LAST: never one taken out of the film, whose H.264 is lossy)
      rm -f "$film" "$film.textrec"
    done
  done
done
echo "squeeze: $(wc -l < $OUT/faults.txt) faults, $OUT/faults.txt"
