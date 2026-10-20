#!/bin/bash
# still.fail's screens (sffix's fixture modes, src/sfscreens) drawn in mbui's Tester, with no window: over the Mac
# host's text as it recorded it for each (screens/text-mac.textrec), at the moment the screen declares (what it opens with),
# what is drawn compared with its reference (src/sfscreens/__snapshot__/MODE.dl, Tester::drawlist: its draw list) and the hash of
# the frame the Mac drew for its picture (shots.sh's, MBUI_SCRIPT=shot).
#   apps/mbui/scripts/screens.sh [test]        the tests (UPDATE=1: the references rewritten)
#   apps/mbui/scripts/screens.sh render        on a Mac (GitHub's macos-15: the references' machine): each screen's
#                                              draw list drawn offscreen, against goldens/render/macos15 (UPDATE=1)
#   apps/mbui/scripts/screens.sh rec [MODE…]   on a Mac: sffix run for each mode (by default every screen of
#                                              src/sfscreens) as shots.sh runs it, its text and last frame kept
#                                              (scripts/screens.py: its section of screens/text-mac.textrec)
#   apps/mbui/scripts/screens.sh rerecord [MODE…]
#                                              a PR that changes what screens draw: on Mini1, the Mac the text is
#                                              kept from (screens/text-mac.txt: its system and fonts, checked;
#                                              NEW_MAC=1: another Mac's, every screen), rec, then the draw lists
#                                              rewritten (test, UPDATE=1) and checked; commit what it changed in
#                                              that PR (an agent: station_task on Mini1, dir its worktree, `back`
#                                              apps/mbui/screens and apps/mbui/src/sfscreens/__snapshot__)
#   apps/mbui/scripts/screens.sh refs [RUN]    the pixel references from mbui-render's artifact (this branch's
#                                              newest run, or RUN): its pictures and machine as goldens/render/macos15
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
# the Mac a run is on: its system's build and its fonts' bytes (what its text depends on)
mac_machine() {
  echo "system $(sw_vers -productVersion) $(sw_vers -buildVersion)"
  echo "fonts $(cat /System/Library/Fonts/SFNS.ttf /System/Library/Fonts/SFNSMono.ttf /System/Library/Fonts/PingFang.ttc 2>/dev/null | md5 -q)"
}
case "${1:-test}" in
  rerecord)
    shift
    [ "$(uname)" = Darwin ] || { echo "screens.sh rerecord: on Mini1, the Mac the text is kept from (station_task)"; exit 1; }
    K=screens/text-mac.txt
    if [ -z "${NEW_MAC:-}" ] && [ -f $K ] && [ "$(mac_machine)" != "$(grep -v '^#' $K)" ]; then
      echo "screens.sh rerecord: the screens' text is kept from another Mac than this one:"
      grep -v '^#' $K | sed 's/^/  kept: /'; mac_machine | sed 's/^/  this: /'
      echo "  rerecord on that Mac (Mini1: station_task); NEW_MAC=1 to keep this one's from now on (every screen)"
      exit 1
    fi
    [ -n "${NEW_MAC:-}" ] && set --
    if [ -n "${NEW_MAC:-}" ] || [ ! -f $K ]; then
      { echo "# The Mac the screens' text is kept from (scripts/screens.sh rerecord): its system and fonts, checked."; mac_machine; } > $K
    fi
    bash "$D/screens.sh" rec "$@" || exit 1
    UPDATE=1 LINES_OUT=20 bash "$D/screens.sh" test >/dev/null 2>&1
    LINES_OUT=40 bash "$D/screens.sh" test || exit 1
    echo "screens.sh rerecord: commit in this PR: apps/mbui/screens/ and apps/mbui/src/sfscreens/__snapshot__/; once its"
    echo "  mbui-render run has drawn them, their pixel references: bash apps/mbui/scripts/screens.sh refs"
    exit 0 ;;
  refs)
    shift
    run=${1:-$(gh run list --workflow mbui-render --commit "$(git rev-parse HEAD)" --json databaseId -q '.[0].databaseId')}
    [ -n "$run" ] || { echo "screens.sh refs: no mbui-render run for $(git rev-parse --short HEAD) (pushed?)"; exit 1; }
    rm -rf out/screens-art
    gh run download "$run" -n screens-render -D out/screens-art || exit 1
    [ -f out/screens-art/machine.txt ] || { echo "screens.sh refs: run $run has no pictures"; exit 1; }
    cp out/screens-art/*.png goldens/render/macos15/
    { grep '^#' goldens/render/macos15.txt 2>/dev/null; cat out/screens-art/machine.txt; } > out/screens-art/head.txt
    mv out/screens-art/head.txt goldens/render/macos15.txt
    git status --short goldens/render | sed 's/^/  /'
    echo "screens.sh refs: run $run's pictures are the references now: commit goldens/render in this PR"
    exit 0 ;;
  rec)
    shift
    modes=${*:-$(sed -n 's/^test "\([^"]*\)" (it : @test.Test).*/\1/p' src/sfscreens/screens_wbtest.mbt)}
    APP=sffix MODE=release bash scripts/mac.sh build >/dev/null || exit 1
    mkdir -p out/screens
    fail=0
    for m in $modes; do
      log=out/screens/$m.log
      MBUI_TEXT_RECORD=1 MBUI_DRAW_LOG=1 MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=$m MBUI_SCRIPT=shot \
        MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/screens ./_build/native/release/build/stillfail/sffix/sffix.exe > $log 2>&1 \
        || { echo "$m: sffix failed ($?): $log"; fail=1; continue; }
      python3 scripts/screens.py keep $m $log || fail=1
    done
    exit $fail ;;
  render)
    # each screen's draw list (src/sfscreens/__snapshot__/MODE.dl) drawn offscreen by mbui's mbui-render, against its
    # pixel reference (goldens/render/macos15/MODE.png: GitHub's macos-15 runner's, mbui's docs/determinism.md), to the
    # byte, once the machine is the references' (goldens/render/macos15.txt: its system's build and its fonts' bytes,
    # checked; its image and cpu said); UPDATE=1 writes the pictures drawn and the machine as the references
    # (out/screens-render has them either way)
    shift
    O=out/screens-render
    G=goldens/render/macos15
    M=goldens/render/macos15.txt
    rm -rf $O; mkdir -p $O $G
    # (mbui's own render app: built in mbui, not as this module's app: no MBUI_APP_MOD)
    (cd "$MBUI_DIR" && env -u MBUI_APP_MOD APP=render MODE=release bash scripts/mac.sh build) > $O/build.log 2>&1 \
      || { echo "screens.sh render: mbui-render did not build"; tail -30 $O/build.log; exit 1; }
    R="$MBUI_DIR/_build/native/release/build/render/render.exe"
    {
      echo "image ${ImageOS:-} ${ImageVersion:-}"
      echo "system $(sw_vers -productVersion) $(sw_vers -buildVersion)"
      # the fonts the pictures' text comes from (the system's, and its Han fallback)
      echo "fonts $(cat /System/Library/Fonts/SFNS.ttf /System/Library/Fonts/SFNSMono.ttf /System/Library/Fonts/PingFang.ttc 2>/dev/null | md5 -q)"
      echo "cpu $(sysctl -n machdep.cpu.brand_string)"
    } > $O/machine.txt
    if [ -z "${UPDATE:-}" ]; then
      if [ ! -f $M ]; then
        echo "screens.sh render: no references yet ($M): this run's pictures and machine ($O) are the artifact to commit (UPDATE=1)"
        stale=1
      fi
      [ -n "${stale:-}" ] || for k in system fonts; do
        want=$(grep "^$k " $M); have=$(grep "^$k " $O/machine.txt)
        if [ "$want" != "$have" ]; then
          echo "screens.sh render: the references are out of date, not the screens: made on \"$want\", this machine is \"$have\""
          echo "  make them all again in one PR from this run's artifact ($O: its pictures and machine.txt, UPDATE=1), saying so"
          stale=1
        fi
      done
    fi
    fail=0
    for dl in src/sfscreens/__snapshot__/*.dl; do
      m=$(basename "$dl" .dl)
      MBUI_DL=$PWD/$dl MBUI_DL_PNG=$PWD/$O/$m.png "$R" 2>/dev/null || { echo "$m: not drawn"; fail=1; continue; }
      if [ -n "${UPDATE:-}" ]; then
        cp $O/$m.png $G/$m.png
      elif [ -z "${stale:-}" ] && ! cmp -s $O/$m.png $G/$m.png; then
        echo "$m: not its reference ($G/$m.png; this run's is $O/$m.png)"
        changed="${changed:+$changed }$m"
        fail=1
      fi
    done
    [ -n "${UPDATE:-}" ] && cp $O/machine.txt $M
    [ -n "${stale:-}" ] && { echo "screens drawn offscreen: $(ls $O/*.png | wc -l | tr -d ' '), not compared (no references, or out of date: above)"; exit 1; }
    echo "screens drawn offscreen: $(ls $O/*.png | wc -l | tr -d ' '), against their references: $([ $fail = 0 ] && echo the same || echo not all)"
    if [ -n "${changed:-}" ]; then
      echo "drawn otherwise: $changed"
      echo "  a PR that changes them: their pictures from this run, committed in it: bash apps/mbui/scripts/screens.sh refs"
    fi
    exit $fail ;;
  test)
    F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
    moon test --target js -p stillfail/sfscreens ${UPDATE:+--update} 2>&1 | grep -v "$F" | tail -${LINES_OUT:-60}
    exit ${PIPESTATUS[0]} ;;
  *) sed -n 2,9p "$0"; exit 2 ;;
esac
