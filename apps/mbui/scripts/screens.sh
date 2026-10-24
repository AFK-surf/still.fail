#!/bin/bash
# still.fail's screens (sffix's fixture modes, src/sfapp/screens_wbtest.mbt) drawn in mbui's Tester, with no window: over the Mac
# host's text as it recorded it for each (screens/text-mac.textrec), at the moment the screen declares (what it opens
# with), idle there and its corners by the rule. What they draw is not compared with mbui's own drawing (a kept draw
# list, a Mac's frame, an offscreen picture): what still.fail's screens are held to is Android's app, the original.
#   apps/mbui/scripts/screens.sh [test]        the tests
#   apps/mbui/scripts/screens.sh rec [MODE…]   on a Mac (Mini1: station_task): sffix run for each mode (by default every
#                                              screen of screens_wbtest.mbt) as shots.sh runs it, its text kept
#                                              (scripts/screens.py: its section of screens/text-mac.textrec), for a
#                                              screen whose text the Mac has not given yet
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
case "${1:-test}" in
  rec)
    shift
    modes=${*:-$(sed -n 's/^test "\([^"]*\)" {.*/\1/p' src/sfapp/screens_wbtest.mbt)}
    APP=sffix MODE=release bash scripts/mac.sh build >/dev/null || exit 1
    mkdir -p out/screens
    fail=0
    # the moment each screen's picture is of, on the run's own clock: past what every screen opens with (a page
    # sliding in, a sheet rising, a flash), as each screen's test checks (screens_wbtest.mbt `opening`; it fails, not
    # waits, where one would still move); the Mac takes it there (MBUI_SHOT_MS), never on its being settled
    shot_ms=3000
    for m in $modes; do
      log=out/screens/$m.log
      # (a phone's screens: on a phone's system, pointed at by a finger, as screens_wbtest.mbt draws them)
      MBUI_PLATFORM=android MBUI_TEXT_RECORD=1 MBUI_DRAW_LOG=1 MBUI_BENCH=-1 MBUI_WIN=390x844 MBUI_FIXTURE=$m MBUI_SCRIPT=shot MBUI_SHOT_MS=$shot_ms \
        MBUI_SHOT_NAME=$m MBUI_SHOT_DIR=$PWD/out/screens ./_build/native/release/build/stillfail/sffix/sffix.exe > $log 2>&1 \
        || { echo "$m: sffix failed ($?): $log"; fail=1; continue; }
      python3 scripts/screens.py keep $m $log || fail=1
    done
    exit $fail ;;
  test)
    F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
    moon_test_native -p stillfail/sfapp --file screens_wbtest.mbt ${UPDATE:+--update} 2>&1 | grep -v "$F" | tail -${LINES_OUT:-60}
    exit ${PIPESTATUS[0]} ;;
  *) sed -n 2,10p "$0"; exit 2 ;;
esac
