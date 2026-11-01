#!/bin/bash
# What breaks the corner rule, seen: sffix's made-up screens filmed offscreen in this Mac's text (src/sffilm,
# scripts/film.sh) in a window, each one's corner faults said (mbui's corners.mbt, the drive step `corners`) and its
# last frame kept as a picture with what breaks the rule outlined (red: the box in the corner; yellow: the container
# whose corner it is in): out/corners/<window>-<lang>/<mode>.png, the faults in out/corners/faults.txt.
#   scripts/corners.sh [WINDOW LANG MODE]…   the screens given, three words each (a list on stdin when none, each line
#                                            perhaps with a drive step after them: `tapxy 830 450`, a pane beside it
#                                            brought over)
# WINDOW: phone390, phone360 (a phone's), touch600 (a tablet's, medium), tablet840, tablet1280 (expanded), desk600,
# desk1280 (a Mac's: its window's corners 16; desk390 one made as narrow as a phone), win600, win1280 (Windows 11's: 8); LANG: zh or en.
# fold890: a fold half open, its crease across (a small screen wider than a phone: tabletop.mbt).
# duo390, duo951: an iPhone Duo's, upright and on its side, the system's bars beside the app (theirs not filmed).
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
FF=$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)
APP=sffilm MODE=release bash scripts/mac.sh build >/dev/null || exit 1
EXE=./_build/native/release/build/stillfail/sffilm/sffilm.exe
mkdir -p out/corners
: > out/corners/faults.txt
rm -f out/corners/failed.txt
if [ $# -gt 0 ]; then printf '%s %s %s\n' "$@"; else cat; fi | while read -r win lang mode step; do
  [ -n "$mode" ] || continue
  # (a drive step after them may be several, `;` between them)
  step=${step//;/$'\n'}
  # (a desktop's window rounded as its system draws it: a Mac's 16, Windows 11's 8; a phone's or a tablet's app fills
  # its screen)
  corner=0
  # (an iPhone Duo's: the system's bars for the app's tabs, MBUI_FILM_NAV_ABLE; what the system draws of them not filmed)
  nav=0
  case $win in
    phone390) w=390; h=844; platform=2; system='' ;;
    phone360) w=360; h=740; platform=2; system='' ;;
    touch600) w=600; h=900; platform=2; system='system {"size_class":{"width":"medium","height":"medium"}}' ;;
    fold890) w=890; h=626; platform=2; system='system {"fold":{"hinge":"half","divisions":[{"x":0,"y":300,"w":890,"h":30}]}}' ;;
    touch839) w=839; h=900; platform=2; system='system {"size_class":{"width":"medium","height":"medium"}}' ;;
    tablet840) w=840; h=900; platform=2; system='system {"size_class":{"width":"expanded","height":"medium"}}' ;;
    tablet1280) w=1280; h=900; platform=2; system='system {"size_class":{"width":"expanded","height":"medium"}}' ;;
    duo390) w=390; h=844; platform=1; nav=1; system='system {"bars":{"top":0,"bottom":20,"left":0,"right":0}}' ;;
    duo951) w=951; h=669; platform=1; nav=1; system='system {"bars":{"top":0,"bottom":20,"left":0,"right":84}}' ;;
    desk390) w=390; h=760; platform=0; system=''; corner=16 ;;
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
  # (the run's whole log kept, <mode>.log; no picture of a run before it left to be taken for this one's)
  log="$dir/$mode.log"
  rm -f "$dir/$mode.png" "$dir/$mode-marked.png" "$dir/$mode.fail.png"
  MBUI_LOCALE=$lang MBUI_FIXTURE=$mode MBUI_WIN=${w}x$h MBUI_FILM_PLATFORM=$platform MBUI_FILM_SCALE=2 MBUI_FILM_WINDOW_CORNER=$corner MBUI_FILM_NAV_ABLE=$nav \
    MBUI_FILM="$PWD/$film" MBUI_FILM_LAST="$PWD/$dir/$mode.png" MBUI_FILM_DRIVE="$PWD/$script" "$EXE" > "$log" 2>&1
  rc=$?
  grep -a 'DRIVE CORNER' "$log" | sed 's|^.*DRIVE CORNER ||' > "$said"
  # (a run that did not pass every step, exit 0 and say DRIVE PASS, failing none: its picture no picture of the run,
  # kept as <mode>.fail.png, and corners.sh fails)
  if [ $rc -ne 0 ] || ! grep -aq 'DRIVE PASS' "$log" || grep -aq 'DRIVE FAIL' "$log"; then
    echo "corners.sh: $win $lang $mode did not pass (rc $rc): $(grep -a 'DRIVE FAIL' "$log" | head -1)" >&2
    [ -f "$dir/$mode.png" ] && mv "$dir/$mode.png" "$dir/$mode.fail.png"
    # (told past the loop, which runs in a pipe's subshell)
    echo "$win $lang $mode" >> out/corners/failed.txt
    continue
  fi
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
  # (the last frame as drawn, MBUI_FILM_LAST: never one taken out of the film, whose H.264 is lossy)
  [ -s "$dir/$mode.png" ] &&
    "$FF" -loglevel error -y -i "$dir/$mode.png" -vf "null$boxes" "$dir/$mode-marked.png" && rm -f "$film" "$film.textrec"
done
echo "corners: $(wc -l < out/corners/faults.txt) faults, out/corners/faults.txt"
[ ! -s out/corners/failed.txt ]
