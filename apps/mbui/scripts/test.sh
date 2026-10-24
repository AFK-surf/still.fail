#!/bin/bash
# This module's tests against mbui's fake host (no window): still.fail's design system, its pages (over the fixtures),
# the media screens' parts and the core client's, the screens (src/sfapp/screens_wbtest.mbt, scripts/screens.sh), then the flows seen
# again over their runs' cores (src/sfreplay/steps.mbt). UPDATE=1 refreshes snapshots. TARGETS: the targets they run
# on (native by default, as the apps are built; CI's check-mbui: native on Linux, and on macOS on main). PARTS: which
# of the two (app: the design system, the pages, the screens, gallery and player; replay: the core and the flows seen
# again), both by default; check-mbui runs each on a runner of its own. SFAPP_SHARDS: how many processes sfapp's test
# files are run in side by side (5); 1, the pages' files all in one (the two screen sweeps a process each beside
# them), as check-mbui runs them: what one file leaves behind that a later one trips on shows only there. mbui's own:
# its scripts/test.sh.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
F='^Warning\|^ *│\|^ *╭\|^ *╰\|^─\|^ *[0-9]* │'
code=0
for t in ${TARGETS:-native}; do
  echo "=== $t"
  # (native, on any system: a test's program links no host's code, its host the Tester's fake (mbui/hostapi). Built
  # --release as the apps are, its C split and compiled in parallel by mbui's scripts/mbc (moon's cc on PATH): on
  # macos-15 the tests ran in 15 s against debug's 144 s (2026-10-20). An object made of the same inputs (by content)
  # is kept: a build over the last one's objects (mbui-check.yml's native cache) compiles only the units whose
  # functions changed. clang where there is one, as on macOS (MBC_REAL_CC says otherwise). Without ThinLTO unless
  # MBC_LTO says (its link is 30-40 s a test; main's run has it on: mbui-check.yml).)
  mode="--target $t"
  # (mbui's scripts/env.sh native_tests: the C split by mbui's scripts/mbc, units kept by content in MBC_STORE)
  if [ $t = native ]; then native_tests "$A"; mode=$NATIVE; fi
  # (the parts' packages in one moon test, which runs a package's tests in one executable and the packages side by
  # side. The flows in one package, src/sfreplay/flows: each test package is a program of the whole app, its C
  # compiled apart, and five of them compiled the same change five times over; on CI's four cores the replay part was
  # 194 s with them apart and 140 s together, 2026-10-22; sfreplay's own two tests there too: its whitebox test was
  # one more program of the whole app, linked with ThinLTO on main in 120 s beside the flows' 118, 2026-10-23)
  pkgs=""
  if [[ " ${PARTS:-app replay} " = *" app "* ]]; then
    # (the screens' tests in sfapp's own, screens_wbtest.mbt: a package of their own was a second program of the whole
    # app, compiled again on every change, 88 s of a branch's app part with sfapp's own 92, 2026-10-23)
    pkgs="-p stillfail/sf -p stillfail/sfapp -p stillfail/sfapp/settings -p stillfail/gallery -p stillfail/player"
    # (with ThinLTO, MBC_LTO=thin: only the program of the whole app. What ThinLTO's tests are for is the code that
    # ships, built as it ships, inlined across its units; all of it is in sfapp's test, run with the whole app's tests.
    # The smaller programs are parts of the same code, each linked again with ThinLTO for its own few tests: five
    # links a part side by side, 35-69 s each after a change, 2026-10-23, 40022031382; their tests run without it)
    [ "${MBC_LTO:-0}" = thin ] && pkgs="-p stillfail/sfapp"
  fi
  if [[ " ${PARTS:-app replay} " = *" replay "* ]]; then
    if [ "${MBC_LTO:-0}" = thin ]; then pkgs="$pkgs -p stillfail/sfreplay/flows"; else
    # (not sfreplay: no test of its own is left there, and its package was two empty programs of the whole app, 29 s
    # of the replay part's compile, 2026-10-24)
    pkgs="$pkgs -p stillfail/core -p stillfail/sfreplay/flows"
    fi
    # (a test under a directory of its own there is in no package this runs: a branch from before brought one back)
    for g in src/sfreplay/flows/*/; do
      [ -d "$g" ] || continue
      echo "test.sh: $g: the flows' tests are in src/sfreplay/flows itself, one package (its tests here are never run)" >&2
      code=1
    done
  fi
  # The kinds of test program a package has none of (internal: a test in its own files; blackbox: *_test.mbt;
  # whitebox: *_wbtest.mbt), which moon builds anyway, each the whole app, and never runs: scripts/mbc puts a stand-in
  # in their place (MBC_EMPTY_TESTS)
  empty=""
  for p in $pkgs; do
    [ "$p" = -p ] && continue
    d=src/${p#stillfail/}; n=$(basename "$d"); [ -d "$d" ] || continue
    [ -n "$(ls "$d"/*.mbt 2>/dev/null | grep -vE '_(wb)?test\.mbt$' | xargs grep -l '^test ' 2>/dev/null)" ] || empty="$empty ${p#stillfail/}/$n.internal_test"
    [ -n "$(ls "$d"/*_test.mbt 2>/dev/null | grep -v '_wbtest\.mbt$')" ] || empty="$empty ${p#stillfail/}/$n.blackbox_test"
    [ -n "$(ls "$d"/*_wbtest.mbt 2>/dev/null)" ] || empty="$empty ${p#stillfail/}/$n.whitebox_test"
  done
  export MBC_EMPTY_TESTS="$empty"
  # The app part's small packages' programs (the library's, the settings', gallery's, player's: a few tests each, the
  # whole of mbui in each) compiled without optimising (MBC_LIGHT_TESTS): a change to mbui compiled its units again in
  # each of them beside sfapp's, ~80 s of four programs' compile on CI's four cores, 2026-10-24, 40127533069
  light=""
  for p in $pkgs; do
    case $p in -p | stillfail/sfapp | stillfail/core | stillfail/sfreplay/*) continue ;; esac
    n=$(basename "$p")
    light="$light ${p#stillfail/}/$n.internal_test ${p#stillfail/}/$n.blackbox_test ${p#stillfail/}/$n.whitebox_test"
  done
  export MBC_LIGHT_TESTS="$light"
  out=$(mktemp)
  # Built first on its own (TIMES=1, as CI's: each said with how long it took; its errors shown by the run), then run.
  s=$(date +%s)
  moon test $mode $pkgs --build-only > /dev/null 2>&1
  [ -z "${TIMES:-}" ] || echo "test.sh: built in $(( $(date +%s) - s )) s"
  s=$(date +%s)
  # (moon runs a program's tests one after another: sfapp's, the screens and every screen's squeeze among them, were
  # one core's 71 s of the app part's run while the other packages' were done, 2026-10-24. Its files in SFAPP_SHARDS
  # moon tests side by side over the build made, the other packages in one more: two moon tests at once go as fast
  # as one, 7 s for 14 on Studio)
  runs=("$pkgs")
  if [[ " $pkgs " = *" -p stillfail/sfapp "* ]]; then
    files=(src/sfapp/*_wbtest.mbt)
    n=${SFAPP_SHARDS:-5}
    runs=("$(echo " $pkgs " | sed 's| -p stillfail/sfapp | |')")
    # (the files that sweep every screen, each a Tester from scratch per screen (screens, squeeze: 10.7 and 7.8 of the
    # 39 s on Studio, 2026-10-25; corners, every screen in five windows and both languages: 64), a process each beside
    # the pages', so the run takes the longest of them, not their sum)
    sweeps=(src/sfapp/screens_wbtest.mbt src/sfapp/squeeze_wbtest.mbt src/sfapp/corners_wbtest.mbt)
    pages=()
    for f in "${files[@]}"; do [[ " ${sweeps[*]} " = *" $f "* ]] || pages+=("$f"); done
    for f in "${sweeps[@]}"; do [ -f "$f" ] && runs+=("$f"); done
    if [ "$n" = 1 ]; then
      # (one: the files that test the pages in one process, every one after the ones moon runs before it, so what one
      # leaves behind that a later one trips on shows (shards, a process each, hide it))
      runs+=("${pages[*]}")
    else
      for ((k = 0; k < n; k++)); do
        shard=()
        for ((i = k; i < ${#pages[@]}; i += n)); do shard+=("${pages[i]}"); done
        [ ${#shard[@]} = 0 ] || runs+=("${shard[*]}")
      done
    fi
  fi
  pids=()
  for i in "${!runs[@]}"; do
    # (a run of nothing is none: moon test of no package would be every package's)
    [ -n "${runs[i]// /}" ] || continue
    moon test $mode ${runs[i]} ${UPDATE:+--update} > "$out.$i" 2>&1 &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait $p || code=1; done
  for i in "${!runs[@]}"; do [ -f "$out.$i" ] && cat "$out.$i"; rm -f "$out.$i"; done > "$out"
  grep -v "$F" "$out" | grep -v '^Total tests' | tail -${LINES_OUT:-60}
  grep '^Total tests' "$out"
  [ -z "${TIMES:-}" ] || echo "test.sh: run in $(( $(date +%s) - s )) s"
  # (the core's answers a test asked and found not kept, src/sfkept: scripts/kept has the core work them out; KEPT_ASKS:
  # where it takes them from)
  asks=$(grep -c 'kept-answers-ask {' "$out")
  if [ "$asks" != 0 ]; then
    [ -n "$KEPT_ASKS" ] && grep 'kept-answers-ask {' "$out" >> "$KEPT_ASKS"
    echo "test.sh: $asks of the core's answers asked and not kept (src/sfkept): scripts/kept keeps them" >&2
    code=1
  fi
  rm -f "$out"
done
exit $code
