#!/bin/bash
# mbui-render (src/render) on Windows, in Git Bash with MoonBit and MSVC (as scripts/win.sh): a Tester's draw list
# (scripts/render_dl.sh) drawn offscreen by the Direct3D 11 renderer on WARP (win_render.cpp
# mb_render_init_offscreen), twice (the program run anew each time): the pictures, the same to the byte, and the
# machine.
#   scripts/render_windows.sh            out/render/{controls-1,controls-2,controls}.png, machine.txt
#   scripts/render_windows.sh against    out/render/controls.png against goldens/render/windows-controls.png, on the
#                                        machine they were made on (goldens/render/windows.txt)
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
. "$D/render_dl.sh"
cd "$D/.."
O=out/render
pwq() { powershell -NoProfile -Command "$1" | tr -d '\r'; }
case "${1:-run}" in
  run)
    rm -rf $O
    render_dl $O/controls.dl
    APP=render bash "$D/win.sh" build
    EXE=out/win/mod/_build/native/release/build/render/render.exe
    # WARP pinned (.github/actions/warp: Microsoft.Direct3D.WARP's d3d10warp.dll, WARP_DLL), beside the program, which
    # loads it before the system's: the pictures drawn by one WARP whatever the runner's image has (an image rolled
    # out to some runners and not others drew the same commit two ways, 39416332991)
    if [ -n "${WARP_DLL:-}" ]; then cp "$WARP_DLL" "$(dirname $EXE)/d3d10warp.dll"; fi
    for n in 1 2; do
      MBUI_DL="$(cygpath -w "$PWD/$O/controls.dl")" MBUI_DL_PNG="$(cygpath -w "$PWD/$O/controls-$n.png")" ./$EXE 2> $O/run-$n.err ||
        { cat $O/run-$n.err; exit 1; }
      cat $O/run-$n.err
    done
    warp_dll=$(sed -n 's/^WARP //p' $O/run-1.err | tr -d '\r' | head -1)
    [ -n "$warp_dll" ] || { echo "render_windows: the program said not which WARP drew it"; exit 1; }
    if [ -n "${WARP_DLL:-}" ] && ! printf '%s' "$warp_dll" | grep -qi 'build.render.d3d10warp.dll$'; then
      echo "render_windows: drawn by $warp_dll, not the pinned WARP beside the program"; exit 1
    fi
    # lines drawn as they are (no reference: checked); Windows' python is `python`
    MBUI_DL="$(cygpath -w "$PWD/$O/lines.dl")" MBUI_DL_PNG="$(cygpath -w "$PWD/$O/lines.png")" ./$EXE
    "$D/chk" lines $O/lines.png
    MBUI_DL="$(cygpath -w "$PWD/$O/shapes.dl")" MBUI_DL_PNG="$(cygpath -w "$PWD/$O/shapes.png")" ./$EXE
    "$D/chk" shapes $O/shapes.png
    MBUI_DL="$(cygpath -w "$PWD/$O/contained.dl")" MBUI_DL_PNG="$(cygpath -w "$PWD/$O/contained.png")" ./$EXE
    "$D/chk" contained $O/contained.png
    MBUI_DL_FROM="$(cygpath -w "$PWD/$O/partial-a.dl")" MBUI_DL="$(cygpath -w "$PWD/$O/partial-b.dl")" \
      MBUI_DL_PNG="$(cygpath -w "$PWD/$O/partial.png")" ./$EXE
    render_partial windows
    md5sum $O/controls-1.png $O/controls-2.png
    if ! cmp -s $O/controls-1.png $O/controls-2.png; then
      echo "render_windows: the two runs' pictures differ"
      exit 1
    fi
    cp $O/controls-1.png $O/controls.png
    {
      echo "draw list $(md5sum < $O/controls.dl | cut -c1-32)"
      echo "picture $(md5sum < $O/controls.png | cut -c1-32)"
      echo "image ${ImageOS:-} ${ImageVersion:-}"
      echo "system $(pwq '[Environment]::OSVersion.VersionString')"
      echo "warp $(pwq "(Get-Item '$warp_dll').VersionInfo.FileVersion")"
      echo "dwrite $(pwq '(Get-Item C:\Windows\System32\DWrite.dll).VersionInfo.FileVersion')"
      # the fonts the text comes from (Segoe UI, its fallbacks for Han: win_text.cpp)
      echo "fonts $(cat /c/Windows/Fonts/segoeui*.ttf /c/Windows/Fonts/msyh*.ttc /c/Windows/Fonts/simsun.ttc 2>/dev/null | md5sum | cut -c1-32)"
      echo "cpu $(pwq '(Get-CimInstance Win32_Processor).Name')"
    } | tee $O/machine.txt
    ;;
  against)
    render_against windows "system warp dwrite fonts"
    ;;
esac
