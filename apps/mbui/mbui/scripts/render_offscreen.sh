#!/bin/bash
# The references' draw list (goldens/render/controls.dl, kept: scripts/render_dl.sh) drawn
# offscreen by mbui-render (src/render), no window: the picture and its md5, and the machine it was drawn on.
# And a rounded clip's two draw lists (clip-cut, clip-box) drawn so, the same picture to the byte.
#   scripts/render_offscreen.sh        out/render/{controls.dl,controls.png,clip-*.{dl,png},machine.txt}
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
O=out/render
rm -rf $O; mkdir -p $O
cp goldens/render/controls.dl $O/controls.dl
APP=render bash scripts/mac.sh build >/dev/null
MBUI_DL=$PWD/$O/controls.dl MBUI_DL_PNG=$PWD/$O/controls.png ./_build/native/release/build/render/render.exe
# a rounded clip (src/kitdemo/gallery/dl_print_wbtest.mbt rounded_clip): a box filled by what it cuts, the same picture as the
# box filled itself, to the byte
# lines (src/kitdemo/gallery/dl_print_wbtest.mbt lines_shown) drawn as they are: no reference, checked (scripts/chk lines)
MBUI_DL_PRINT=lines moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
  awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > $O/lines.dl
[ -s $O/lines.dl ] || { echo "render_offscreen: no lines draw list"; exit 1; }
MBUI_DL=$PWD/$O/lines.dl MBUI_DL_PNG=$PWD/$O/lines.png ./_build/native/release/build/render/render.exe
"$D/chk" lines $O/lines.png
# shapes (src/kitdemo/gallery/dl_print_wbtest.mbt shapes_shown) drawn as they are: checked (scripts/chk shapes)
MBUI_DL_PRINT=shapes moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
  awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > $O/shapes.dl
[ -s $O/shapes.dl ] || { echo "render_offscreen: no shapes draw list"; exit 1; }
MBUI_DL=$PWD/$O/shapes.dl MBUI_DL_PNG=$PWD/$O/shapes.png ./_build/native/release/build/render/render.exe
"$D/chk" shapes $O/shapes.png
MBUI_DL_PRINT=contained moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
  awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > $O/contained.dl
[ -s $O/contained.dl ] || { echo "render_offscreen: no contained draw list"; exit 1; }
MBUI_DL=$PWD/$O/contained.dl MBUI_DL_PNG=$PWD/$O/contained.png ./_build/native/release/build/render/render.exe
"$D/chk" contained $O/contained.png
# partial redraw (docs/partial-redraw.md): a spinner's two moments (src/kitdemo/gallery/dl_print_wbtest.mbt
# partial_shown), the second drawn only where it differs from the first, the same picture as the second drawn whole,
# to the byte
for k in partial-a partial-b; do
  MBUI_DL_PRINT=$k moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
    awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > $O/$k.dl
  [ -s $O/$k.dl ] || { echo "render_offscreen: no $k draw list"; exit 1; }
done
MBUI_DL_FROM=$PWD/$O/partial-a.dl MBUI_DL=$PWD/$O/partial-b.dl MBUI_DL_PNG=$PWD/$O/partial.png \
  ./_build/native/release/build/render/render.exe
if cmp -s $O/partial.png $O/partial.whole.png; then
  echo "render_offscreen: a frame drawn only where it differs is the frame drawn whole, to the byte"
else
  echo "render_offscreen: a frame drawn only where it differs is not the frame drawn whole ($O/partial.png, partial.whole.png)"
  exit 1
fi
for k in clip-cut clip-box; do
  MBUI_DL_PRINT=$k moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
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
