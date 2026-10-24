#!/bin/bash
# Records a flow's trace again from its test (src/sfreplay/flows/NAME_test.mbt), one command, nothing kept by hand:
# the test's steps, as its first order takes them, written as a scripted run (src/sfreplay/emit.mbt: FLOW_EMIT), run
# in the app against a local still.fail of its own (scripts/e2e-local.sh up, e2e/run.sh with MBUI_CORE_TRACE=1), its
# conversation made the test's trace again (scripts/trace make) and what changed of its asks said (scripts/trace diff),
# then the test run over the new trace.
#
#   scripts/rerecord.sh NAME…        each a test's NAME (drive_list) or an end-to-end flow kept in e2e/flows (18-drive-upload)
#                                    a flow needs before it (run as it is, its trace not kept); in the order given
#
# The run's mark ({T}, e2e-<tag>) and the station's directory are the old trace's, so the words the test looks for are
# the same. One run for all NAMEs: they share their mark (a batch recorded together). macOS, a machine that runs the
# e2e (scripts/e2e-local.sh). E2E_PORT, E2E_RELAY as e2e-local.sh's; E2E_KEEP=1 leaves the local still.fail up;
# MAX_BYTES as scripts/trace make's (a long text's bytes kept).
# KEEP_NEW=1: a test that fails over its new trace keeps it all the same.
set -u
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
die() { echo "rerecord: $*" >&2; exit 1; }
[ $# -gt 0 ] || die "which tests? (scripts/rerecord.sh drive_list …)"
command -v moon > /dev/null || die "no moon on PATH (MoonBit: MBUI_TOOLS, or its bin on PATH)"
mkdir -p "$A/out" && TMP=$(mktemp -d "$A/out/rerecord.XXXXXX") || exit 1
tag=""; station=""; tests=""; i=0
# a run's first flow is given the account by its environment (its trace has `migrate`): sign-in first, kept apart;
# unless the first test's own trace is a first start (it has `migrate`: what the app does once, as asking about
# notifications, is in it), where that test is the run's first flow
first_start=""
for n in "$@"; do
  [ -f "e2e/flows/$n.drive" ] && break
  tn=$(grep -o '@sfreplay\.trace("[^"]*")' $(ls src/sfreplay/flows/"${n}_test.mbt" 2> /dev/null | head -1) 2> /dev/null | head -1 | sed 's/.*trace("//; s/")//')
  [ -n "$tn" ] && grep -q '"call":"migrate"' "e2e/traces/$tn.trace" 2> /dev/null && first_start=1
  break
done
if [ -z "$first_start" ] && [ -f e2e/flows/01-signin.drive ]; then cp e2e/flows/01-signin.drive "$TMP/00-01-signin.drive"; fi
for n in "$@"; do
  i=$((i + 1)); idx=$(printf %02d $i)
  if [ -f "e2e/flows/$n.drive" ]; then
    cp "e2e/flows/$n.drive" "$TMP/$idx-$n.drive"
    [ -f "e2e/flows/$n.check" ] && cp "e2e/flows/$n.check" "$TMP/$idx-$n.check"
    continue
  fi
  test=$(ls src/sfreplay/flows/"${n}_test.mbt" 2> /dev/null | head -1)
  [ -n "$test" ] || die "no test src/sfreplay/flows/${n}_test.mbt, nor flow e2e/flows/$n.drive"
  tn=$(grep -o '@sfreplay\.trace("[^"]*")' "$test" | head -1 | sed 's/.*trace("//; s/")//')
  [ -n "$tn" ] || die "$test names no @sfreplay.trace(…)"
  trace=e2e/traces/$tn.trace
  [ -f "$trace" ] || die "no $trace"
  # its mark: the six digits the test's words and its trace share most; its station's directory as the trace has it
  t=$("$D/trace" mark "$test" "$trace")
  s=$(grep -o '/tmp/mb[A-Za-z0-9-]*' "$trace" | sort | uniq -c | sort -rn | awk 'NR==1 {print $2}')
  # (a test whose words hold no mark of its run looks for none: it goes with the others' mark)
  [ -z "$t" ] || [ -z "$tag" ] || [ "$tag" = "$t" ] || die "$n was recorded with the mark $t, the others before it $tag: rerecord them apart"
  [ -n "$t" ] && tag=$t; [ -n "$s" ] && station=$s
  echo "rerecord: $n ← $test (trace $trace, mark ${t:-none of its own}${s:+, station $s})"
  FLOW_EMIT="$TMP/$idx-$n.drive" moon_test_native "$test" > "$TMP/$idx-$n.test.log" 2>&1
  [ -s "$TMP/$idx-$n.drive" ] || { grep -a 'Error\]\|error:\|failed\|^flow:' "$TMP/$idx-$n.test.log" | head -20 | cut -c1-300; die "$test wrote no script"; }
  # (from a starting point (E2E_START), the app's core already made: the first start's `migrate`, which a test over a
  # first start's trace waits for, is not asked again)
  if [ -n "${E2E_START:-}" ]; then
    grep -v '^answered migrate$' "$TMP/$idx-$n.drive" > "$TMP/$idx-$n.drive.tmp" && mv "$TMP/$idx-$n.drive.tmp" "$TMP/$idx-$n.drive"
  fi
  tests="$tests $idx-$n:$trace:$test"
done
[ -n "$tests" ] || die "no test among: $*"
# bytes kept as the old traces kept them: their largest beside a message (a novel read whole was kept whole), unless
# MAX_BYTES says otherwise
if [ -z "${MAX_BYTES:-}" ]; then
  MAX_BYTES=$("$D/trace" maxbytes $(for x in $tests; do r=${x#*:}; echo "${r%%:*}"; done))
  export MAX_BYTES
fi
# (none of them with a mark of its own: a new one)
[ -n "$tag" ] || tag=$(date +%H%M%S)
echo "rerecord: the scripts written ($TMP)"; ls "$TMP"/*.drive | sed 's/^/  /'
# (each step once the app is settled, as the Tester's steps are taken: what came of the last one in, its page loaded;
# until drive's named events take its place)
# (the host's answers kept too (MBUI_TEXT_RECORD=1: its fonts' measures, a word's bounds, a picture's sizes), for the
# replay's page laid out as the run's was: what the app tells the core of where the list is (client.focus's end,
# chat.place) the same; TEXT_RECORD=0 leaves them out)
[ "${TEXT_RECORD:-1}" = 0 ] || export MBUI_TEXT_RECORD=1
export E2E_STATION=${station:-${E2E_STATION:-}} E2E_TAG=$tag E2E_FLOWS=$TMP MBUI_CORE_TRACE=1 MBUI_CORE_TRACE_BYTES=$MAX_BYTES
[ -n "$E2E_STATION" ] || unset E2E_STATION
bash scripts/e2e-local.sh down > /dev/null 2>&1
bash scripts/e2e-local.sh up > "$TMP/up.log" 2>&1 || { tail -30 "$TMP/up.log"; die "the local still.fail did not come up"; }
bash e2e/run.sh mac 2>&1 | tee "$TMP/run.log" | grep -a '^PASS\|^FAIL\|flows passed\|DRIVE FAIL'
rc=${PIPESTATUS[0]}
[ -n "${E2E_KEEP:-}" ] || bash scripts/e2e-local.sh down > /dev/null 2>&1
# (a flow its run failed keeps its old trace; the others are recorded again)
[ $rc = 0 ] || echo "rerecord: not all of the run passed: those that failed keep their traces ($TMP/run.log, out/e2e/mac/)"
code=$rc
# (those whose trace is still the old one, and why: a batch may hold traces of two builds of the app)
kept=""
for x in $tests; do
  name=${x%%:*}; rest=${x#*:}; trace=${rest%%:*}; test=${rest#*:}
  if ! grep -aq '^DRIVE PASS' "out/e2e/mac/$name.log" 2>/dev/null; then
    why=$(grep -a -m1 'DRIVE FAIL line' "out/e2e/mac/$name.log" 2>/dev/null | sed 's/^ *DRIVE FAIL //' | cut -c1-160)
    echo "  $test: its run failed, its trace kept as it was:"; grep -a 'DRIVE FAIL' "out/e2e/mac/$name.log" 2>/dev/null | head -2 | cut -c1-300
    cp "out/e2e/mac/$name.log" "$TMP/$name.run.log" 2>/dev/null
    kept="$kept
  $(basename "$trace"): the run failed (${why:-no DRIVE FAIL line})"
    continue
  fi
  cp "$trace" "$TMP/$(basename "$trace").old"
  "$D/trace" make "out/e2e/mac/$name.log" "$(basename "$trace" .trace)"
  "$D/trace" diff "$TMP/$(basename "$trace").old" "$trace" | sed "s|^|  $(basename "$trace" .trace): |"
  if moon_test_native "$test" > "$TMP/$name.after.log" 2>&1; then echo "  $test: passes"; else
    echo "  $test: fails over the new trace ($TMP/$name.after.log):"; grep -a '^flow:\|assert_idle' "$TMP/$name.after.log" | head -5 | cut -c1-300; code=1
    # (the new trace is the run's; the test does not hold over it: the old one back, said; KEEP_NEW=1 keeps the new
    # one, as when what fails is a core answer not yet kept: scripts/kept, then the test again)
    [ -n "${KEEP_NEW:-}" ] || cp "$TMP/$(basename "$trace").old" "$trace"
    # (the run's log kept with it: the next run's takes its place in out/e2e/mac)
    cp "out/e2e/mac/$name.log" "$TMP/$name.run.log" 2>/dev/null
    kept="$kept
  $(basename "$trace"): its test fails over the new one ($(grep -a -m1 '^flow:\|assert_idle' "$TMP/$name.after.log" | cut -c1-160))"
  fi
done
if [ -n "$kept" ]; then
  echo "rerecord: these keep their old traces (recorded by an earlier build of the app than the others):$kept"
fi
exit $code
