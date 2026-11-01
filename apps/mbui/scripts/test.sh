#!/bin/bash
# This module's tests against mbui's fake host (no window): still.fail's design system, its pages (over the fixtures),
# the media screens' parts and the core client's, the screens (src/sfapp/screens_wbtest.mbt, scripts/screens.sh), then the flows seen
# again over their runs' cores (src/sfreplay/steps.mbt). UPDATE=1 refreshes snapshots. TARGETS: the targets they run
# on (native by default, as the apps are built; CI's check-mbui: native on Linux, and on macOS on main). PARTS: which
# of the two (app: the design system, the pages, the screens, gallery and player; replay: the core and the flows seen
# again), both by default; check-mbui runs each on a runner of its own. SFAPP_SHARDS: how many processes sfapp's test
# files are run in side by side (5); 1, the pages' files all in one (the screen sweeps a process each beside them):
# what one file leaves behind that a later one trips on shows best there, and check-mbui's run of the day runs them so
# (a push's in 4). mbui's own: its scripts/test.sh.
# APP_EXE (with APP_INFO, its tests' list, __whitebox_test_info.json): sfapp's test program built elsewhere (check-mbui's
# app-build job's), its runs asked of it directly (scripts/testexe; TESTEXE: that tool built elsewhere too, beside it),
# nothing built here. APP_BUILD_OUT: sfapp's test program built only, it, its tests' list and the tool put in that
# directory for them.
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
  if [ $t = native ] && [ -z "${APP_EXE:-}" ]; then native_tests "$A"; mode=$NATIVE; fi
  # (the parts' packages in one moon test, which runs a package's tests in one executable and the packages side by
  # side. The flows in one package, src/sfreplay/flows: each test package is a program of the whole app, its C
  # compiled apart, and five of them compiled the same change five times over; on CI's four cores the replay part was
  # 194 s with them apart and 140 s together, 2026-10-22; sfreplay's own two tests there too: its whitebox test was
  # one more program of the whole app, linked with ThinLTO on main in 120 s beside the flows' 118, 2026-10-23)
  pkgs=""
  if [[ " ${PARTS:-app replay} " = *" app "* ]]; then
    # (the screens' tests in sfapp's own, screens_wbtest.mbt: a package of their own was a second program of the whole
    # app, compiled again on every change, 88 s of a branch's app part with sfapp's own 92, 2026-10-23)
    # (sfpages' own tests too: the pages moved there from sfapp brought theirs, run by nothing until 2026-10-25)
    pkgs="-p stillfail/sf -p stillfail/sfpages -p stillfail/sfapp -p stillfail/sfapp/settings -p stillfail/gallery -p stillfail/player -p stillfail/pinyin -p stillfail/keyboard"
    # (APP_GROUP=k/n: one runner's share of sfapp's runs, app_group_of below, each building sfapp's program alone;
    # APP_GROUP=pkgs: the small packages' run alone, on a runner of its own. Their five programs were built by the
    # first group beside sfapp's, each much of the app again: its build 168-209 s after a change where the others'
    # was 57-89, the first's job the check's longest, 2026-10-29, 40807235675)
    if [ "${APP_GROUP:-}" = pkgs ]; then pkgs="-p stillfail/sf -p stillfail/sfpages -p stillfail/sfapp/settings -p stillfail/gallery -p stillfail/player -p stillfail/pinyin -p stillfail/keyboard"
    elif [ -n "${APP_GROUP:-}" ]; then pkgs="-p stillfail/sfapp"; fi
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
  [ -n "${APP_EXE:-}" ] || moon test $mode $pkgs --build-only > /dev/null 2>&1
  [ -z "${TIMES:-}" ] || [ -n "${APP_EXE:-}" ] || echo "test.sh: built in $(( $(date +%s) - s )) s"
  # (sfapp's test program and its tests' list put where APP_BUILD_OUT says, for the jobs that run it: nothing run)
  if [ -n "${APP_BUILD_OUT:-}" ]; then
    b=_build/native/release/test/stillfail/sfapp
    [ -f $b/sfapp.whitebox_test.exe ] || { moon test $mode $pkgs --build-only 2>&1 | grep -v "$F" | tail -40; exit 1; }
    mkdir -p "$APP_BUILD_OUT" && cp $b/sfapp.whitebox_test.exe $b/__whitebox_test_info.json "$APP_BUILD_OUT/" &&
      cp "$(bash "$D/testexe" path)" "$APP_BUILD_OUT/testexe" || exit 1
    echo "test.sh: sfapp's test program put in $APP_BUILD_OUT ($(du -h $b/sfapp.whitebox_test.exe | cut -f1))"
    exit 0
  fi
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
    # the pages', so the run takes the longest of them, not their sum. corners' tests, one a language, a process each:
    # the one file was the run's longest, 39 s on Studio beside the pages' 34, 2026-10-25; on CI's four cores the app
    # part's run went from 44 s to 67 with it. squeeze's screens measured in corners' sweep, on the frames it opens
    # (all of them among its own): squeeze's 32 s process on CI, the same screens opened again, gone, 2026-10-25)
    # (the squeeze sweep again with what people wrote at its longest, squeeze_said_wbtest.mbt: every screen once more,
    # a process of its own)
    # (contrast's, every screen in every window in the dark theme, contrast_wbtest.mbt: left among the pages, their
    # process went from 96 s to 129 on CI and the app part's run with it, 2026-10-26; a process of its own)
    # (kept_rows_kinds_wbtest.mbt's, every kind of message the fixtures hold opened twice, its rows kept and built,
    # in five tests: 70 of the pages' 128 s, each file run alone on CI, 2026-10-27, 40344557870; among the pages one
    # of their two processes was 207 s, the other 84; two processes of its own, then four: the third runner's job was
    # its first's 0-5 alone in one process, three of its four cores waiting, 65 s of its 183 on main 99a74aa4, 2026-10-31)
    sweeps=(src/sfapp/screens_wbtest.mbt:1 src/sfapp/corners_wbtest.mbt:3 src/sfapp/squeeze_said_wbtest.mbt:1
      src/sfapp/contrast_wbtest.mbt:1 src/sfapp/kept_rows_kinds_wbtest.mbt:4)
    pages=()
    for f in "${files[@]}"; do [[ " ${sweeps[*]} " = *" $f:"* ]] || pages+=("$f"); done
    for w in "${sweeps[@]}"; do
      f=${w%:*} k=${w##*:}
      [ -f "$f" ] || continue
      # (in k runs of its tests by their index: moon test FILE --index FROM-TO, the tests in the file's order)
      m=$(grep -c '^test "' "$f")
      if [ "$k" -le 1 ] || [ "$m" -le 1 ]; then runs+=("$f"); continue; fi
      for ((j = 0; j < k; j++)); do
        a=$((j * m / k)) b=$(((j + 1) * m / k))
        [ $b -gt $a ] && runs+=("$f --index $a-$b")
      done
    done
    if [ "$n" = 1 ]; then
      # (one: the files that test the pages in one process, every one after the ones moon runs before it, so what one
      # leaves behind that a later one trips on shows (shards, a process each, hide it))
      runs+=("${pages[*]}")
    elif [ -n "${APP_EXE:-}" ]; then
      # (on a program built elsewhere: the pages in one run whose n programs each take the next file (exe_run's
      # xargs -P), not dealt out beforehand: by name round four one took 75 s while another took 21, 2026-11-01)
      runs+=("${pages[*]}")
      export APP_JOBS=$n
    else
      for ((k = 0; k < n; k++)); do
        shard=()
        for ((i = k; i < ${#pages[@]}; i += n)); do shard+=("${pages[i]}"); done
        [ ${#shard[@]} = 0 ] || runs+=("${shard[*]}")
      done
    fi
  fi
  # The flows seen again (src/sfreplay/flows, one program): their files in REPLAY_SHARDS moon tests side by side (4:
  # three left a core of CI's four to the core's tests, 0 s of the run, while the flows' took 53, main bb091fcd
  # 41265169250, 2026-11-01),
  # the core's tests in another. One moon test ran them one after another, 83 s of the replay part's run on CI's four
  # cores, the part the pipeline's longest on a branch (mbui-parts-nodes, 40573326799, 2026-10-28).
  if [[ " $pkgs " = *" -p stillfail/sfreplay/flows "* ]] && [ "${MBC_LTO:-0}" != thin ]; then
    flows=(src/sfreplay/flows/*_test.mbt)
    n=${REPLAY_SHARDS:-4}
    rest=()
    for r in "${runs[@]}"; do rest+=("$(echo " $r " | sed 's| -p stillfail/sfreplay/flows | |')"); done
    runs=("${rest[@]}")
    fx=_build/native/release/test/stillfail/sfreplay/flows/flows.blackbox_test.exe
    if [ $t = native ] && [ -z "${UPDATE:-}" ] && [ -f $fx ]; then
      # (native: their files in one run of the program built above, whose n programs each take the next file
      # (exe_run's xargs -P), not dealt out beforehand: dealt by name round three, 68 s, 43 and 41, the replay
      # part's 183 s the pipeline's longest job, chat-opener-links 41248997629, 2026-11-01)
      runs+=("@flows ${flows[*]}")
    else
      for ((k = 0; k < n; k++)); do
        shard=()
        for ((i = k; i < ${#flows[@]}; i += n)); do shard+=("${flows[i]}"); done
        [ ${#shard[@]} = 0 ] || runs+=("${shard[*]}")
      done
    fi
  fi
  # Which of APP_GROUP's n runners a run is on (k of 1..n). Four (check-mbui's): each two or three of the runs that
  # were the app part's longest side by side on one runner's four cores, 2026-10-27 (corners 188 s and 171, kept_rows'
  # 187 and 147, the pages' 174, contrast's 117, screens' 77, squeeze_said's 49, the packages' 10, all nine at once:
  # the part's run 188 s). Alone on four runners (40425191188) corners in Chinese was 92 s, every other run 52 s or less:
  # its press's room and contrast a third corners run since, on the first: on the fourth beside the pages and contrast,
  # the three slowed each other to 85, 81 and 38 s while the first ran 38 (adb-card-direct, 40430050749). A run named
  # nowhere here is the first's, never left out. (Screens' then on the second: beside both Chinese corners runs on the
  # first it slowed them to 74 and 62 s, the second running 37, 40430734093.) (Contrast's on the first since the small
  # packages went to a runner of their own: the fourth's job was the part's longest, the pages' 72 s beside contrast's 25,
  # while the first ran its two corners runs in 26, fix/back-cancel-follows-system 40828675419, mbui-panel-ground
  # 40843559612, 2026-10-29.) (Then on the third: the first's job beside the corners runs was the part's longest but the
  # pages', 152 s and 179, the second's and third's 96 and 101, main 9a748590, 40942683567, 2026-10-30.) (On a runner of
  # its own since: beside kept_rows' two runs the third's was then the longest, 162-185 s against the first's 110-118,
  # fix/side-bar-under-band 40955953763, msg-highlight 40955729359; wherever it went it was some 50 s of that runner's.)
  # (kept_rows' second run on the second since: with both of them the third's job was the part's longest after the
  # pages', the second's the shortest, 65-123 s against 157-182, fix/swipe-archive-undo 40972095755, mbui-node-asks
  # 40971809575, main ff97a641 40971760122, 2026-10-30.)
  # (kept_rows' in four since, the first three on the third, side by side on its cores, the last on the second beside
  # its three: the third's one process of 65 s was its job's longest, 183 s on main 99a74aa4, 2026-10-31.)
  app_group_of() {
    local n=$1
    shift
    if [ "$n" != 4 ]; then echo 1; return; fi
    case "$1 $2 $3" in
      "-p "*) echo 1 ;;
      "src/sfapp/corners_wbtest.mbt --index 0-"*) echo 1 ;;
      "src/sfapp/corners_wbtest.mbt --index 2-"*) echo 1 ;;
      "src/sfapp/screens_wbtest.mbt  ") echo 2 ;;
      "src/sfapp/corners_wbtest.mbt --index "*) echo 2 ;;
      "src/sfapp/squeeze_said_wbtest.mbt  ") echo 2 ;;
      "src/sfapp/kept_rows_kinds_wbtest.mbt --index 8-"*) echo 2 ;;
      "src/sfapp/kept_rows_kinds_wbtest.mbt "*) echo 3 ;;
      "src/sfapp/contrast_wbtest.mbt  ") echo contrast ;;
      *) [ $# -gt 2 ] && echo 4 || echo 1 ;;
    esac
  }
  if [ -n "${APP_GROUP:-}" ] && [[ " $pkgs " = *" -p stillfail/sfapp "* ]]; then
    mine=()
    for r in "${runs[@]}"; do
      [ -n "${r// /}" ] || continue
      # (APP_GROUP=contrast: contrast's run alone, on a runner of its own, beside the four)
      if [ "$APP_GROUP" = contrast ]; then [ "$(app_group_of 4 $r)" = contrast ] && mine+=("$r")
      else [ "$(app_group_of "${APP_GROUP#*/}" $r)" = "${APP_GROUP%/*}" ] && mine+=("$r"); fi
    done
    runs=("${mine[@]}")
  fi
  run_name() {
    [ "$1" = @flows ] && shift
    case " $* " in
      *" -p "*) echo "the packages$(echo " $* " | sed 's| -p stillfail/| |g')" ;;
      *" --index "*) echo "$(basename "$1") (tests $3)" ;;
      *) [ $# -le 2 ] && echo $(basename -a "$@") || echo "$# files ($(basename "$1") ...)" ;;
    esac
  }
  # exe_run EXE INFO JOBS PKG FILE… | FILE --index FROM-TO: a run on a test program built already, JOBS of it side by
  # side, each taking the next part when done with one (xargs -P); tools/testexe says what to ask it and what it said
  exe_run() {
    local exe=$1 info=$2 j=$3 pkg=$4 d c
    shift 4
    d=$(mktemp -d)
    "$TESTEXE" parts "$info" "$j" "$@" > "$d/parts" || { rm -rf "$d"; return 2; }
    [ ! -s "$d/parts" ] || sed "s|^|$d/|" "$d/parts" | xargs -P "$j" -L 1 sh -c \
      's=$(date +%s); "$0" "$2" > "$1.out" 2>&1; echo "$? $(($(date +%s) - s))" > "$1.code"' "$exe"
    "$TESTEXE" said "$info" "$d" "$pkg"
    c=$?
    rm -rf "$d"
    return $c
  }
  # (the tool, built before the runs side by side, not by each: TESTEXE, or scripts/testexe's)
  if [ -n "${APP_EXE:-}" ] || [[ " ${runs[*]} " = *" @flows "* ]]; then
    [ -n "${TESTEXE:-}" ] || TESTEXE=$(bash "$D/testexe" path) || exit 1
  fi
  pids=()
  for i in "${!runs[@]}"; do
    # (a run of nothing is none: moon test of no package would be every package's)
    [ -n "${runs[i]// /}" ] || continue
    # (each run's time with TIMES: the part's run is the longest of them, and which one it is is said)
    { if [ "${runs[i]%% *}" = @flows ]; then
        f=_build/native/release/test/stillfail/sfreplay/flows
        exe_run $f/flows.blackbox_test.exe $f/__blackbox_test_info.json ${REPLAY_SHARDS:-4} stillfail/sfreplay/flows \
          ${runs[i]#@flows } > "$out.$i" 2>&1
      elif [ -n "${APP_EXE:-}" ]; then
        exe_run "$APP_EXE" "$APP_INFO" ${APP_JOBS:-1} stillfail/sfapp ${runs[i]} > "$out.$i" 2>&1
      else moon test $mode ${runs[i]} ${UPDATE:+--update} > "$out.$i" 2>&1; fi; c=$?
      echo "$(( $(date +%s) - s )) s: $(run_name ${runs[i]})" > "$out.time.$i"
      exit $c; } &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait $p || code=1; done
  for i in "${!runs[@]}"; do [ -f "$out.$i" ] && cat "$out.$i"; rm -f "$out.$i"; done > "$out"
  grep -v "$F" "$out" | grep -v '^Total tests' | tail -${LINES_OUT:-60}
  grep '^Total tests' "$out"
  [ -z "${TIMES:-}" ] || cat "$out".time.* 2>/dev/null | sort -rn | sed 's/^/test.sh: a run of /'
  rm -f "$out".time.*
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
