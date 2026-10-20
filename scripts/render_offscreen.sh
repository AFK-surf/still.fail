#!/bin/bash
# A Tester's draw list (kitdemo's controls page over mini1's kept text, src/kitdemo/dl_print_wbtest.mbt) drawn
# offscreen by mbui-render (src/render), no window: the picture and its md5, and the machine it was drawn on.
#   scripts/render_offscreen.sh        out/render/{controls.dl,controls.png,machine.txt}
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
{
  echo "draw list $(md5 -q $O/controls.dl)"
  echo "picture $(md5 -q $O/controls.png)"
  echo "system $(sw_vers -productVersion) $(sw_vers -buildVersion)"
  echo "cpu $(sysctl -n machdep.cpu.brand_string)"
  echo "image ${ImageOS:-} ${ImageVersion:-}"
} | tee $O/machine.txt
