#!/bin/bash
# What breaks the corner rule, seen: sffix's made-up screens filmed offscreen in this Mac's text (src/sffilm,
# scripts/film.sh) in a window, each one's corner faults said (mbui's corners.mbt, the drive step `corners`) and its
# last frame kept as a picture with what breaks the rule outlined (red: the box in the corner; yellow: the container
# whose corner it is in): out/corners/<window>-<lang>/<mode>.png, the faults in out/corners/faults.txt.
#   scripts/corners.sh [WINDOW LANG MODE]…   the screens given, three words each (a list on stdin when none, each line
#                                            perhaps with a drive step after them: `tapxy 830 450`, a pane beside it
#                                            brought over)
# WINDOW: phone390, phone360 (a phone's), touch600 (a tablet's, medium), tablet840, tablet1280 (expanded), desk600,
# desk1280 (a Mac's: its window's corners 16), win600, win1280 (Windows 11's: 8); LANG: zh or en.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
FF=$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)
APP=sffilm MODE=release bash scripts/mac.sh build >/dev/null || exit 1
EXE=./_build/native/release/build/stillfail/sffilm/sffilm.exe
mkdir -p out/corners
: > out/corners/faults.txt
if [ $# -gt 0 ]; then printf '%s %s %s\n' "$@"; else cat; fi | while read -r win lang mode step; do
  [ -n "$mode" ] || continue
  step=${step//;/$'\n'}
  # (a desktop's window rounded as its system draws it: a Mac's 16, Windows 11's 8; a phone's or a tablet's app fills
  # its screen)
  corner=0
  case $win in
    phone390) w=390; h=844; platform=2; system='' ;;
    phone360) w=360; h=740; platform=2; system='' ;;
    touch600) w=600; h=900; platform=2; system='system {"size_class":{"width":"medium","height":"medium"}}' ;;
    touch839) w=839; h=900; platform=2; system='system {"size_class":{"width":"medium","height":"medium"}}' ;;
    tablet840) w=840; h=900; platform=2; system='system {"size_class":{"width":"expanded","height":"medium"}}' ;;
    tablet1280) w=1280; h=900; platform=2; system='system {"size_class":{"width":"expanded","height":"medium"}}' ;;
    desk600) w=600; h=760; platform=0; system=''; corner=16 ;;
    desk1280) w=1280; h=800; platform=0; system=''; corner=16 ;;
    win600) w=600; h=760; platform=3; system=''; corner=8 ;;
    win1280) w=1280; h=800; platform=3; system=''; corner=8 ;;
    *) echo "corners.sh: no window $win" >&2; continue ;;
  esac
  dir="out/corners/$win-$lang"
  mkdir -p "$dir"
  script="$dir/$mode.drive"
  printf '%s\ntimeout 4000\nwait 1200\n%s\nwait 1200\ncorners\nexit\n' "$system" "$step" > "$script"
  film="$dir/$mode.mp4"
  said="$dir/$mode.txt"
  MBUI_LOCALE=$lang MBUI_FIXTURE=$mode MBUI_WIN=${w}x$h MBUI_FILM_PLATFORM=$platform MBUI_FILM_SCALE=2 MBUI_FILM_WINDOW_CORNER=$corner \
    MBUI_FILM="$PWD/$film" MBUI_FILM_DRIVE="$PWD/$script" "$EXE" 2>&1 | grep 'DRIVE CORNER' \
    | sed 's|^.*DRIVE CORNER ||' > "$said"
  sed "s|^|$win-$lang $mode: |" "$said" >> out/corners/faults.txt
  # the last frame as it is (<mode>.png) and with each fault outlined just outside its edges (<mode>-marked.png): the
  # box in the corner red, its container yellow (a line that starts with the container, "wants corner … for", the other
  # way round), at the film's scale (2)
  boxes=""
  while IFS= read -r f; do
    n=0
    first=red; second=yellow
    case $f in *": wants corner "*", for "*) first=yellow; second=red ;; esac
    for at in $(printf '%s\n' "$f" | grep -oE 'at -?[0-9.]+,-?[0-9.]+ [0-9.]+×[0-9.]+' | sed 's/^at //; s/ /:/; s/×/:/'); do
      IFS=':' read -r xy bw bh <<< "$at"
      bx=${xy%,*}; by=${xy#*,}
      color=$first; [ $n -gt 0 ] && color=$second
      boxes="$boxes,drawbox=x=$(echo "$bx*2-5" | bc):y=$(echo "$by*2-5" | bc):w=$(echo "$bw*2+10" | bc):h=$(echo "$bh*2+10" | bc):color=$color@0.9:t=3"
      n=$((n + 1))
      [ $n -ge 2 ] && break
    done
  done < "$said"
  "$FF" -loglevel error -y -sseof -0.05 -i "$film" -frames:v 1 "$dir/$mode.png" &&
    "$FF" -loglevel error -y -i "$dir/$mode.png" -vf "null$boxes" "$dir/$mode-marked.png" && rm -f "$film" "$film.textrec"
done
echo "corners: $(wc -l < out/corners/faults.txt) faults, out/corners/faults.txt"
