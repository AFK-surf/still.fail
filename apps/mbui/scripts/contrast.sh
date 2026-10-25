#!/bin/bash
# What is too faint to be seen, seen: sffix's made-up screens filmed offscreen in this Mac's text (src/sffilm,
# scripts/film.sh) in a window and a theme, each one's contrast faults said (mbui's contrast.mbt, the drive step
# `contrast`) and its last frame kept as a picture with each fault outlined in red: out/contrast/<window>-<theme>/
# <mode>.png and <mode>-marked.png, the faults in out/contrast/faults.txt.
#   scripts/contrast.sh [WINDOW THEME MODE]…   the screens given, three words each (a list on stdin when none, each
#                                              line perhaps with a drive step after them)
# WINDOW: as scripts/corners.sh's (phone360, touch600, tablet840, desk600, desk1280, …); THEME: light or dark.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
FF=$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)
APP=sffilm MODE=release bash scripts/mac.sh build >/dev/null || exit 1
EXE=./_build/native/release/build/stillfail/sffilm/sffilm.exe
mkdir -p out/contrast
: > out/contrast/faults.txt
if [ $# -gt 0 ]; then printf '%s %s %s\n' "$@"; else cat; fi | while read -r win theme mode step; do
  [ -n "$mode" ] || continue
  corner=0
  case $win in
    phone390) w=390; h=844; platform=2; system='' ;;
    phone360) w=360; h=740; platform=2; system='' ;;
    touch600) w=600; h=900; platform=2; system='system {"size_class":{"width":"medium","height":"medium"}}' ;;
    tablet840) w=840; h=900; platform=2; system='system {"size_class":{"width":"expanded","height":"medium"}}' ;;
    desk600) w=600; h=760; platform=0; system=''; corner=16 ;;
    desk1280) w=1280; h=800; platform=0; system=''; corner=16 ;;
    *) echo "contrast.sh: no window $win" >&2; continue ;;
  esac
  dark=0
  [ "$theme" = dark ] && dark=1
  dir="out/contrast/$win-$theme"
  mkdir -p "$dir"
  script="$dir/$mode.drive"
  printf '%s\ntimeout 4000\nwait 1200\n%s\nwait 1200\ncontrast\nexit\n' "$system" "$step" > "$script"
  film="$dir/$mode.mp4"
  said="$dir/$mode.txt"
  MBUI_LOCALE=zh MBUI_DARK=$dark MBUI_FIXTURE=$mode MBUI_WIN=${w}x$h MBUI_FILM_PLATFORM=$platform MBUI_FILM_SCALE=2 \
    MBUI_FILM_WINDOW_CORNER=$corner MBUI_FILM="$PWD/$film" MBUI_FILM_DRIVE="$PWD/$script" "$EXE" 2>&1 \
    | grep 'DRIVE CONTRAST' | sed 's|^.*DRIVE CONTRAST ||' > "$said"
  sed "s|^|$win-$theme $mode: |" "$said" >> out/contrast/faults.txt
  # the last frame as it is (<mode>.png) and with each fault outlined just outside its edges (<mode>-marked.png), at
  # the film's scale (2)
  boxes=""
  while IFS= read -r f; do
    at=$(printf '%s\n' "$f" | grep -oE 'at -?[0-9.]+,-?[0-9.]+ [0-9.]+×[0-9.]+' | head -1 | sed 's/^at //; s/ /:/; s/×/:/')
    [ -n "$at" ] || continue
    IFS=':' read -r xy bw bh <<< "$at"
    bx=${xy%,*}; by=${xy#*,}
    boxes="$boxes,drawbox=x=$(echo "$bx*2-4" | bc):y=$(echo "$by*2-4" | bc):w=$(echo "$bw*2+8" | bc):h=$(echo "$bh*2+8" | bc):color=red@0.9:t=3"
  done < "$said"
  "$FF" -loglevel error -y -sseof -0.05 -i "$film" -frames:v 1 "$dir/$mode.png" &&
    "$FF" -loglevel error -y -i "$dir/$mode.png" -vf "null$boxes" "$dir/$mode-marked.png" && rm -f "$film" "$film.textrec"
done
echo "contrast: $(wc -l < out/contrast/faults.txt) faults, out/contrast/faults.txt"
