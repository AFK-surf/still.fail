#!/bin/bash
# mbui-render (src/render) on Linux (as scripts/linux.sh builds it): a Tester's draw list (scripts/render_dl.sh) drawn
# offscreen by the GLES 3 renderer on EGL's surfaceless platform, Mesa's llvmpipe where there is no GPU
# (linux_render.c mb_render_init_offscreen), twice (the program run anew each time): the pictures, the same to the
# byte, and the machine.
#   scripts/render_linux.sh            out/render/{controls-1,controls-2,controls}.png, machine.txt
#   scripts/render_linux.sh against    out/render/controls.png against goldens/render/linux-controls.png, on the
#                                      machine they were made on (goldens/render/linux.txt)
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
. "$D/render_dl.sh"
cd "$D/.."
O=out/render
case "${1:-run}" in
  run)
    rm -rf $O
    render_dl $O/controls.dl
    APP=render bash "$D/linux.sh" build
    EXE=out/linux/mod/_build/native/release/build/render/render.exe
    # (llvmpipe whatever GPU the machine has: the references are of Mesa's software renderer)
    export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
    for n in 1 2; do
      MBUI_DL="$PWD/$O/controls.dl" MBUI_DL_PNG="$PWD/$O/controls-$n.png" ./$EXE 2> $O/run-$n.err ||
        { cat $O/run-$n.err; exit 1; }
      cat $O/run-$n.err
    done
    # lines and shapes drawn as they are (no reference: checked)
    MBUI_DL="$PWD/$O/lines.dl" MBUI_DL_PNG="$PWD/$O/lines.png" ./$EXE
    "$D/chk" lines $O/lines.png
    MBUI_DL="$PWD/$O/shapes.dl" MBUI_DL_PNG="$PWD/$O/shapes.png" ./$EXE
    "$D/chk" shapes $O/shapes.png
    MBUI_DL="$PWD/$O/contained.dl" MBUI_DL_PNG="$PWD/$O/contained.png" ./$EXE
    "$D/chk" contained $O/contained.png
    MBUI_DL_FROM="$PWD/$O/partial-a.dl" MBUI_DL="$PWD/$O/partial-b.dl" MBUI_DL_PNG="$PWD/$O/partial.png" ./$EXE
    render_partial linux
    for k in matte-fill matte-fill-reference matte-contain matte-contain-reference matte-inset matte-inset-reference; do
      MBUI_DL="$PWD/$O/$k.dl" MBUI_DL_PNG="$PWD/$O/$k.png" ./$EXE
    done
    render_matte linux
    md5sum $O/controls-1.png $O/controls-2.png
    if ! cmp -s $O/controls-1.png $O/controls-2.png; then
      echo "render_linux: the two runs' pictures differ"
      exit 1
    fi
    cp $O/controls-1.png $O/controls.png
    {
      echo "draw list $(md5sum < $O/controls.dl | cut -c1-32)"
      echo "picture $(md5sum < $O/controls.png | cut -c1-32)"
      echo "image ${ImageOS:-} ${ImageVersion:-}"
      echo "system $(. /etc/os-release && echo "$PRETTY_NAME") $(uname -m)"
      # what draws it: Mesa (its llvmpipe), and what sets the text (Pango, HarfBuzz, FreeType, as linux_text.c has them)
      echo "mesa $(dpkg-query -W -f '${Version}' libgl1-mesa-dri 2> /dev/null)"
      echo "text pango $(pkg-config --modversion pango) harfbuzz $(pkg-config --modversion harfbuzz) freetype $(pkg-config --modversion freetype2)"
      # the fonts the text comes from (the system's sans-serif, Noto Sans CJK SC for Han, Noto Color Emoji)
      echo "fonts $(for f in sans-serif 'Noto Sans CJK SC' 'Noto Color Emoji'; do fc-match -f '%{file}\n' "$f"; done | sort -u | xargs cat | md5sum | cut -c1-32)"
      echo "cpu $(sed -n 's/^model name\s*: //p' /proc/cpuinfo | head -1)$(uname -m | grep -q aarch64 && echo ' (arm64)')"
    } | tee $O/machine.txt
    ;;
  against)
    render_against linux "system mesa text fonts"
    ;;
esac
