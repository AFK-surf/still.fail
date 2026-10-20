#!/bin/bash
# The renderer against the host (macOS): kitdemo's controls page as the host draws it in its window (MBUI_SCRIPT=shot),
# its run kept as it goes (its text and frames); that run drawn again in a Tester (src/kitdemo/dl_print_wbtest.mbt), its
# last frame as a draw list, drawn offscreen by mbui-render (src/render): the two pictures of that frame the same to
# the byte.
#   scripts/render_check.sh            out/render-check/{controls.dl,render.png,host.png}
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
O=out/render-check
rm -rf $O; mkdir -p $O
APP=render bash scripts/mac.sh build >/dev/null
APP=kitdemo bash scripts/mac.sh build >/dev/null
# the host's run: its picture, and its tape (its text, its frames: MBUI_TEXT_RECORD, MBUI_DRAW_LOG)
MBUI_BENCH=-1 MBUI_SCREEN=controls MBUI_WIN=960x720 MBUI_SCRIPT=shot MBUI_SHOT_NAME=host MBUI_SHOT_DIR=$PWD/$O \
  MBUI_TEXT_RECORD=1 MBUI_DRAW_LOG=1 ./_build/native/release/build/kitdemo/kitdemo.exe > $O/host.log 2>&1 || true
[ -s $O/host.png ] || { echo "render_check: the host took no picture"; grep -a 'SETTLE' $O/host.log | tail -2; exit 1; }
# the same run drawn again in a Tester from its tape: its last frame's draw list (each frame the host's: DLFRAMES)
MBUI_DL_PRINT=1 MBUI_DL_TAPE=$PWD/$O/host.log moon test --target js src/kitdemo/dl_print_wbtest.mbt 2>/dev/null > $O/print.txt
grep -a '^DLFRAMES' $O/print.txt || true
awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' $O/print.txt > $O/controls.dl
[ -s $O/controls.dl ] || { echo "render_check: no draw list"; exit 1; }
MBUI_DL=$PWD/$O/controls.dl MBUI_DL_PNG=$PWD/$O/render.png ./_build/native/release/build/render/render.exe
if cmp -s $O/render.png $O/host.png; then
  echo "render_check: the draw list drawn offscreen is the host's picture, to the byte ($(md5 -q $O/render.png))"
else
  echo "render_check: the draw list drawn offscreen is not the host's picture ($(md5 -q $O/render.png) / $(md5 -q $O/host.png))"
  exit 1
fi
