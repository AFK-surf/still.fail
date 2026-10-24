#!/bin/bash
# What is squeezed, seen: sffix's made-up screens (MBUI_FIXTURE modes) filmed offscreen in this Mac's text (src/sffilm,
# scripts/film.sh) in the narrowest windows each frame is drawn in, each one's squeeze faults said (mbui's squeeze.mbt,
# the drive step `squeeze`) and its last frame kept as a picture: out/squeeze/<size>-<lang>/<mode>.png, the faults in
# out/squeeze/faults.txt. For people looking at what does not fit; the checks are the Tester's (squeeze_wbtest.mbt).
#   scripts/squeeze.sh [MODE…]            the modes given, else those of SQUEEZE_MODES (a few dozen of each page)
#   SIZES="touch600 desk701 phone320"     which windows (touchW: a tablet's wide frame, a finger; deskW: a Mac's; phoneW)
#   LANGS="zh en"                         in which of the app's languages
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
FF=$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)
APP=sffilm MODE=release bash scripts/mac.sh build >/dev/null || exit 1
EXE=./_build/native/release/build/stillfail/sffilm/sffilm.exe
MODES=${*:-${SQUEEZE_MODES:-home chat newchat files drive settings-home settings-station settings-profiles}}
mkdir -p out/squeeze
: > out/squeeze/faults.txt
for size in ${SIZES:-touch600 desk701 phone320}; do
  w=${size//[a-z]/}
  case $size in
    touch*) h=900; platform=2; system='system {"size_class":{"width":"regular","height":"regular"}}' ;;
    phone*) h=700; platform=2; system='' ;;
    *) h=760; platform=0; system='' ;;
  esac
  for lang in ${LANGS:-zh en}; do
    dir="out/squeeze/$size-$lang"
    mkdir -p "$dir"
    for mode in $MODES; do
      script="$dir/$mode.drive"
      printf '%s\ntimeout 4000\nwait 1200\nsqueeze\nexit\n' "$system" > "$script"
      film="$dir/$mode.mp4"
      MBUI_LOCALE=$lang MBUI_FIXTURE=$mode MBUI_WIN=${w}x$h MBUI_FILM_PLATFORM=$platform MBUI_FILM_SCALE=2 \
        MBUI_FILM="$PWD/$film" MBUI_FILM_DRIVE="$PWD/$script" "$EXE" 2>&1 | grep 'DRIVE SQUEEZE' \
        | sed "s|^.*DRIVE SQUEEZE |$size-$lang $mode: |" >> out/squeeze/faults.txt
      "$FF" -loglevel error -y -sseof -0.05 -i "$film" -frames:v 1 "$dir/$mode.png" && rm -f "$film" "$film.textrec"
    done
  done
done
echo "squeeze: $(wc -l < out/squeeze/faults.txt) faults, out/squeeze/faults.txt"
