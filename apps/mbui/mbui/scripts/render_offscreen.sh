#!/bin/bash
# A Tester's draw list (kitdemo's controls page over mini1's kept text, src/kitdemo/dl_print_wbtest.mbt) drawn
# offscreen by mbui-render (src/render), no window: the picture and its md5, and the machine it was drawn on.
# And a rounded clip's two draw lists (clip-cut, clip-box) drawn so, the same picture to the byte.
#   scripts/render_offscreen.sh        out/render/{controls.dl,controls.png,clip-*.{dl,png},machine.txt}
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
O=out/render
rm -rf $O; mkdir -p $O
MBUI_DL_PRINT=1 moon test --target js src/kitdemo/dl_print_wbtest.mbt 2>/dev/null |
  awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > $O/controls.dl
[ -s $O/controls.dl ] || { echo "render_offscreen: no draw list"; exit 1; }
APP=render bash scripts/mac.sh build >/dev/null
MBUI_DL=$PWD/$O/controls.dl MBUI_DL_PNG=$PWD/$O/controls.png ./_build/native/release/build/render/render.exe
# a rounded clip (src/kitdemo/dl_print_wbtest.mbt rounded_clip): a box filled by what it cuts, the same picture as the
# box filled itself, to the byte
# lines (src/kitdemo/dl_print_wbtest.mbt lines_shown) drawn as they are: no reference, checked (scripts/lines_check.py)
MBUI_DL_PRINT=lines moon test --target js src/kitdemo/dl_print_wbtest.mbt 2>/dev/null |
  awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > $O/lines.dl
[ -s $O/lines.dl ] || { echo "render_offscreen: no lines draw list"; exit 1; }
MBUI_DL=$PWD/$O/lines.dl MBUI_DL_PNG=$PWD/$O/lines.png ./_build/native/release/build/render/render.exe
python3 "$D/lines_check.py" $O/lines.png
for k in clip-cut clip-box; do
  MBUI_DL_PRINT=$k moon test --target js src/kitdemo/dl_print_wbtest.mbt 2>/dev/null |
    awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > $O/$k.dl
  [ -s $O/$k.dl ] || { echo "render_offscreen: no $k draw list"; exit 1; }
  MBUI_DL=$PWD/$O/$k.dl MBUI_DL_PNG=$PWD/$O/$k.png ./_build/native/release/build/render/render.exe
done
if cmp -s $O/clip-cut.png $O/clip-box.png; then
  echo "render_offscreen: what a rounded clip cuts is the box's own rounded ground, to the byte"
else
  echo "render_offscreen: what a rounded clip cuts is not the box's own rounded ground ($O/clip-cut.png, clip-box.png)"
  exit 1
fi
{
  echo "draw list $(md5 -q $O/controls.dl)"
  echo "picture $(md5 -q $O/controls.png)"
  echo "system $(sw_vers -productVersion) $(sw_vers -buildVersion)"
  echo "gpu $(system_profiler SPDisplaysDataType 2>/dev/null | sed -n 's/^ *Chipset Model: //p' | head -1)"
} | tee $O/machine.txt
