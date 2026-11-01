#!/bin/bash
# mbui-render (src/render) in the browser: a Tester's draw list (scripts/render_dl.sh) drawn by web/host.js's WebGL2
# renderer in headless Chromium on SwiftShader (scripts/render_web.mjs), twice (the browser started anew each time):
# the pictures, the same to the byte, and the machine. Playwright is pinned (PLAYWRIGHT), and with it the browser.
#   scripts/render_web.sh            out/render/{controls-1,controls-2,controls}.png, machine.txt
#   scripts/render_web.sh against    out/render/controls.png against goldens/render/web-controls.png, on the machine
#                                    they were made on (goldens/render/web.txt)
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
. "$D/render_dl.sh"
cd "$D/.."
O=out/render
PLAYWRIGHT=1.64.1
case "${1:-run}" in
  run)
    rm -rf $O
    render_dl $O/controls.dl
    moon build --target js --release src/render 2>&1 | "$D/chk" errs
    S=out/render-web
    rm -rf $S && mkdir -p $S
    cp "$(pkg_build render js release)/render.js" web/render.html web/host.js $S/
    mkdir -p out/node
    if [ "$(cd out/node && node -p "require('./node_modules/playwright/package.json').version" 2>/dev/null)" != $PLAYWRIGHT ]; then
      (cd out/node && { [ -f package.json ] || npm init -y >/dev/null; } && npm i playwright@$PLAYWRIGHT pngjs@7.0.0 >/dev/null)
    fi
    (cd out/node && npx playwright install --with-deps chromium >/dev/null)
    for n in 1 2; do
      node scripts/render_web.mjs $S $O/controls.dl $O/controls-$n.png | tee $O/run-$n.txt
    done
    # lines drawn as they are (no reference: checked)
    node scripts/render_web.mjs $S $O/lines.dl $O/lines.png >/dev/null
    "$D/chk" lines $O/lines.png
    node scripts/render_web.mjs $S $O/shapes.dl $O/shapes.png >/dev/null
    "$D/chk" shapes $O/shapes.png
    node scripts/render_web.mjs $S $O/contained.dl $O/contained.png >/dev/null
    "$D/chk" contained $O/contained.png
    node scripts/render_web.mjs $S $O/partial-b.dl $O/partial.png $O/partial-a.dl
    render_partial web
    for k in matte-fill matte-fill-reference matte-contain matte-contain-reference matte-inset matte-inset-reference; do
      node scripts/render_web.mjs "$S" "$O/$k.dl" "$O/$k.png" >/dev/null
    done
    render_matte web
    md5sum $O/controls-1.png $O/controls-2.png
    if ! cmp -s $O/controls-1.png $O/controls-2.png; then
      echo "render_web: the two runs' pictures differ"
      exit 1
    fi
    cp $O/controls-1.png $O/controls.png
    {
      echo "draw list $(md5sum < $O/controls.dl | cut -c1-32)"
      echo "picture $(md5sum < $O/controls.png | cut -c1-32)"
      echo "image ${ImageOS:-} ${ImageVersion:-}"
      sed -n 's/^browser /browser /p; s/^gl /gl /p' $O/run-1.txt
      # the fonts the page's text can come from (the system's, by fontconfig): their files' bytes
      echo "fonts $(fc-list --format '%{file}\n' | sort -u | xargs md5sum | md5sum | cut -c1-32)"
      echo "system $(. /etc/os-release && echo "$PRETTY_NAME") $(uname -r)"
      echo "cpu $(sed -n 's/^model name\t: //p' /proc/cpuinfo | head -1)"
    } | tee $O/machine.txt
    ;;
  against)
    render_against web "browser fonts"
    ;;
esac
