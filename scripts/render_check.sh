#!/bin/bash
# The renderer against the host (macOS): a screen a Tester drew (kitdemo's controls page over mini1's kept text,
# src/kitdemo/dl_print_wbtest.mbt) as a draw list, drawn offscreen by mbui-render (src/render), and the same page as
# the host draws it in its window (MBUI_SCRIPT=shot): the two pictures the same to the byte.
#   scripts/render_check.sh            out/render-check/{controls.dl,render.png,host.png}
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
O=out/render-check
rm -rf $O; mkdir -p $O
MBUI_DL_PRINT=1 moon test --target js src/kitdemo/dl_print_wbtest.mbt 2>/dev/null |
  awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > $O/controls.dl
[ -s $O/controls.dl ] || { echo "render_check: no draw list"; exit 1; }
APP=render bash scripts/mac.sh build >/dev/null
APP=kitdemo bash scripts/mac.sh build >/dev/null
MBUI_DL=$PWD/$O/controls.dl MBUI_DL_PNG=$PWD/$O/render.png ./_build/native/release/build/render/render.exe
MBUI_BENCH=-1 MBUI_SCREEN=controls MBUI_WIN=960x720 MBUI_SCRIPT=shot MBUI_SHOT_NAME=host MBUI_SHOT_DIR=$PWD/$O \
  ./_build/native/release/build/kitdemo/kitdemo.exe >/dev/null 2>&1
if cmp -s $O/render.png $O/host.png; then
  echo "render_check: the draw list drawn offscreen is the host's picture, to the byte ($(md5 -q $O/render.png))"
else
  echo "render_check: the draw list drawn offscreen is not the host's picture ($(md5 -q $O/render.png) / $(md5 -q $O/host.png))"
  exit 1
fi
