#!/bin/bash
# The differential text test: every string of src/text/testdata/corpus.txt drawn by mbui (src/textdiff) and by the
# platform's own text drawing at the same font, size and place, compared by scripts/textdiff.mjs (advance, ink box,
# pixels within antialiasing): out/textdiff/<host>/report.html shows the worst side by side.
#   scripts/textdiff.sh [mac web android windows]    (default: mac web)
# Each host's run fails when a string differs that src/text/testdata/textdiff-<host>.json does not list as known to;
# UPDATE=1 writes that list from the run. ONLY=<id prefix> draws only those strings. Android runs on the emulator
# (AVD, EMU_PORT as scripts/android.sh has them, booted already); Windows in Git Bash with MSVC (CI: windows.yml).
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
HOSTS=${*:-mac web}
{ echo '// Generated from src/text/testdata/corpus.txt by scripts/textdiff.sh: edit that file, not this one.'
  echo; echo '///|'; echo 'let corpus : String ='; sed 's/^/  #|/' src/text/testdata/corpus.txt; } > src/textdiff/corpus.mbt.new
cmp -s src/textdiff/corpus.mbt.new src/textdiff/corpus.mbt || mv src/textdiff/corpus.mbt.new src/textdiff/corpus.mbt
rm -f src/textdiff/corpus.mbt.new
if [ ! -d out/node/node_modules/pngjs ]; then
  (mkdir -p out/node && cd out/node && { [ -f package.json ] || npm init -y >/dev/null; } && npm i pngjs >/dev/null 2>&1)
fi
WIN=${WIN:-900x800}
fail=0
for h in $HOSTS; do
  O=out/textdiff/$h
  rm -rf $O && mkdir -p $O
  case $h in
    mac)
      APP=textdiff MODE=release bash scripts/mac.sh build >/dev/null || { echo "textdiff: mac build failed"; fail=1; continue; }
      # MBUI_SHAPE_CHECK: Core Text's own layout of every string the ASCII fast path lays out, compared with it
      MBUI_SHAPE_CHECK=1 MBUI_BENCH=-1 MBUI_WIN=$WIN MBUI_TEXTDIFF_ONLY=${ONLY:-} MBUI_SHOT_DIR=$PWD/$O \
        ./_build/native/release/build/textdiff/textdiff.exe > $O/log.txt 2>&1
      checks=$(grep -c "shape check:" $O/log.txt)
      echo "textdiff mac: the ASCII fast path differs from Core Text in $checks strings"
      [ "$checks" = 0 ] || { grep "shape check:" $O/log.txt | head -5; fail=1; } ;;
    web)
      if [ ! -d out/node/node_modules/playwright ]; then
        (cd out/node && npm i playwright >/dev/null 2>&1 && npx playwright install chromium >/dev/null 2>&1)
      fi
      APP=textdiff bash scripts/web.sh build >/dev/null || { echo "textdiff: web build failed"; fail=1; continue; }
      WIN=$WIN QUERY="MBUI_TEXTDIFF_ONLY=${ONLY:-}" NODE_PATH=$PWD/out/node/node_modules node scripts/textdiff-web.mjs $O ;;
    android)
      SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
      ADB="$SDK/platform-tools/adb -s emulator-${EMU_PORT:-5580}"
      APP=textdiff bash scripts/android.sh build >/dev/null || { echo "textdiff: android build failed"; fail=1; continue; }
      $ADB logcat -c
      # the last run's pictures gone (the app not yet installed on a new emulator has none)
      $ADB shell run-as dev.mbui.demo rm -rf files/textdiff 2>/dev/null || true
      APP=textdiff ENV="MBUI_BENCH=-1;MBUI_TEXTDIFF_ONLY=${ONLY:-}" bash scripts/android.sh run
      # the app's own named end, or its crash, as logcat has it (cleared above: this run's)
      $ADB logcat -v brief -m 1 -e "TXD done|FATAL EXCEPTION|Fatal signal" >/dev/null
      $ADB logcat -d -v raw -s mbui:I > $O/log.txt
      grep -q "TXD done" $O/log.txt || { echo "textdiff android: the app did not finish"; fail=1; }
      $ADB exec-out run-as dev.mbui.demo tar cf - -C files/textdiff . | tar xf - -C $O ;;
    windows)
      APP=textdiff bash scripts/win.sh build >/dev/null || { echo "textdiff: windows build failed"; fail=1; continue; }
      MBUI_BENCH=-1 MBUI_WIN=$WIN MBUI_TEXTDIFF_ONLY=${ONLY:-} MBUI_SHOT_DIR="$(cygpath -w "$PWD/$O")" \
        out/win/mod/_build/native/release/build/textdiff/textdiff.exe > $O/log.txt 2>&1 ;;
    *) echo "textdiff: no host $h"; fail=1; continue ;;
  esac
  EXPECT=src/text/testdata/textdiff-$h.json node scripts/textdiff.mjs $O $h || fail=1
done
exit $fail
