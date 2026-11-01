#!/bin/bash
# The renderer against the host (macOS): kitdemo's controls page as the host draws it in its window (MBUI_SCRIPT=shot),
# its run kept as it goes (its text and frames); that run drawn again in a Tester (src/kitdemo/gallery/dl_print_wbtest.mbt), its
# last frame as a draw list, drawn offscreen by mbui-render (src/render): the two pictures of that frame the same to
# the byte.
#   scripts/render_check.sh            out/render-check/{controls.dl,render.png,host.png}
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
. "$D/render_dl.sh"
cd "$D/.."
O=out/render-check
rm -rf $O; mkdir -p $O
APP=render bash scripts/mac.sh build >/dev/null
APP=kitdemo bash scripts/mac.sh build >/dev/null
# the host's run: its picture, and its tape (its text, its frames: MBUI_TEXT_RECORD, MBUI_DRAW_LOG)
MBUI_BENCH=-1 MBUI_SCREEN=controls MBUI_WIN=960x720 MBUI_SCRIPT=shot MBUI_SHOT_NAME=host MBUI_SHOT_DIR=$PWD/$O \
  MBUI_TEXT_RECORD=1 MBUI_DRAW_LOG=1 on_screen ./_build/native/release/build/kitdemo/kitdemo.exe > $O/host.log 2>&1 || true
[ -s $O/host.png ] || { echo "render_check: the host took no picture"; grep -a 'SETTLE' $O/host.log | tail -2; exit 1; }
# the same run drawn again in a Tester from its tape: its last frame's draw list (each frame the host's: DLFRAMES)
MBUI_DL_PRINT=1 MBUI_DL_TAPE=$PWD/$O/host.log moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null > $O/print.txt
grep -a '^DLFRAMES' $O/print.txt || true
awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' $O/print.txt > $O/controls.dl
[ -s $O/controls.dl ] || { echo "render_check: no draw list"; exit 1; }
MBUI_DL=$PWD/$O/controls.dl MBUI_DL_PNG=$PWD/$O/render.png ./_build/native/release/build/render/render.exe
# a rounded clip: a box filled by what it cuts drawn offscreen as the box filled itself, to the byte
# lines (src/kitdemo/gallery/dl_print_wbtest.mbt lines_shown) drawn as they are: no reference, checked (scripts/chk lines)
MBUI_DL_PRINT=lines moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
  awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > $O/lines.dl
[ -s $O/lines.dl ] || { echo "render_check: no lines draw list"; exit 1; }
MBUI_DL=$PWD/$O/lines.dl MBUI_DL_PNG=$PWD/$O/lines.png ./_build/native/release/build/render/render.exe
"$D/chk" lines $O/lines.png
# shapes (src/kitdemo/gallery/dl_print_wbtest.mbt shapes_shown) drawn as they are: checked (scripts/chk shapes)
MBUI_DL_PRINT=shapes moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
  awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > $O/shapes.dl
[ -s $O/shapes.dl ] || { echo "render_check: no shapes draw list"; exit 1; }
MBUI_DL=$PWD/$O/shapes.dl MBUI_DL_PNG=$PWD/$O/shapes.png ./_build/native/release/build/render/render.exe
"$D/chk" shapes $O/shapes.png
MBUI_DL_PRINT=contained moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
  awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > $O/contained.dl
[ -s $O/contained.dl ] || { echo "render_check: no contained draw list"; exit 1; }
MBUI_DL=$PWD/$O/contained.dl MBUI_DL_PNG=$PWD/$O/contained.png ./_build/native/release/build/render/render.exe
"$D/chk" contained $O/contained.png
# partial redraw (docs/partial-redraw.md): a spinner's two moments (src/kitdemo/gallery/dl_print_wbtest.mbt
# partial_shown), the second drawn only where it differs from the first, the same picture as the second drawn whole,
# to the byte
for k in partial-a partial-b; do
  MBUI_DL_PRINT=$k moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
    awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > $O/$k.dl
  [ -s $O/$k.dl ] || { echo "render_check: no $k draw list"; exit 1; }
done
MBUI_DL_FROM=$PWD/$O/partial-a.dl MBUI_DL=$PWD/$O/partial-b.dl MBUI_DL_PNG=$PWD/$O/partial.png \
  ./_build/native/release/build/render/render.exe
if cmp -s $O/partial.png $O/partial.whole.png; then
  echo "render_check: a frame drawn only where it differs is the frame drawn whole, to the byte"
else
  echo "render_check: a frame drawn only where it differs is not the frame drawn whole ($O/partial.png, partial.whole.png)"
  exit 1
fi
for k in clip-cut clip-box; do
  MBUI_DL_PRINT=$k moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
    awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > $O/$k.dl
  [ -s $O/$k.dl ] || { echo "render_check: no $k draw list"; exit 1; }
  MBUI_DL=$PWD/$O/$k.dl MBUI_DL_PNG=$PWD/$O/$k.png ./_build/native/release/build/render/render.exe
done
if cmp -s $O/clip-cut.png $O/clip-box.png; then
  echo "render_check: what a rounded clip cuts is the box's own rounded ground, to the byte ($(md5 -q $O/clip-cut.png))"
else
  echo "render_check: what a rounded clip cuts is not the box's own rounded ground ($(md5 -q $O/clip-cut.png) / $(md5 -q $O/clip-box.png))"
  exit 1
fi
render_matte_dl "$O"
for k in matte-fill matte-fill-reference matte-contain matte-contain-reference matte-inset matte-inset-reference; do
  MBUI_DL="$PWD/$O/$k.dl" MBUI_DL_PNG="$PWD/$O/$k.png" ./_build/native/release/build/render/render.exe
done
render_matte mac "$O"
if cmp -s $O/render.png $O/host.png; then
  echo "render_check: the draw list drawn offscreen is the host's picture, to the byte ($(md5 -q $O/render.png))"
else
  echo "render_check: the draw list drawn offscreen is not the host's picture ($(md5 -q $O/render.png) / $(md5 -q $O/host.png))"
  exit 1
fi
