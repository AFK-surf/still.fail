#!/bin/bash
# Records a flow's trace again from its test (src/sfreplay/flows/NAME_test.mbt), one command, nothing kept by hand:
# the test's steps, as its first order takes them, written as a scripted run (src/sfreplay/emit.mbt: FLOW_EMIT), run
# in the app against a local still.fail of its own (scripts/e2e-local.sh up, e2e/run.sh with MBUI_CORE_TRACE=1), its
# conversation made the test's trace again (scripts/trace.py) and what changed of its asks said (scripts/tracediff.py),
# then the test run over the new trace.
#
#   scripts/rerecord.sh NAME…        each a test's NAME (drive_list) or an end-to-end flow kept in e2e/flows (18-drive-upload)
#                                    a flow needs before it (run as it is, its trace not kept); in the order given
#
# The run's mark ({T}, e2e-<tag>) and the station's directory are the old trace's, so the words the test looks for are
# the same. One run for all NAMEs: they share their mark (a batch recorded together). macOS, a machine that runs the
# e2e (scripts/e2e-local.sh). E2E_PORT, E2E_RELAY as e2e-local.sh's; E2E_KEEP=1 leaves the local still.fail up;
# MAX_BYTES as trace.py's (a long text's bytes kept).
set -u
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
die() { echo "rerecord: $*" >&2; exit 1; }
[ $# -gt 0 ] || die "which tests? (scripts/rerecord.sh drive_list …)"
command -v moon > /dev/null || die "no moon on PATH (MoonBit: MBUI_TOOLS, or its bin on PATH)"
TMP=$(mktemp -d "$A/out/rerecord.XXXXXX")
tag=""; station=""; tests=""; i=0
# a run's first flow is given the account by its environment (its trace has `migrate`): sign-in first, kept apart
if [ -f e2e/flows/01-signin.drive ]; then cp e2e/flows/01-signin.drive "$TMP/00-01-signin.drive"; fi
for n in "$@"; do
  i=$((i + 1)); idx=$(printf %02d $i)
  if [ -f "e2e/flows/$n.drive" ]; then
    cp "e2e/flows/$n.drive" "$TMP/$idx-$n.drive"
    [ -f "e2e/flows/$n.check" ] && cp "e2e/flows/$n.check" "$TMP/$idx-$n.check"
    continue
  fi
  test="src/sfreplay/flows/${n}_test.mbt"
  [ -f "$test" ] || die "no test $test, nor flow e2e/flows/$n.drive"
  ident=$(grep -o '@sfreplay\.trace_[a-z0-9_]*' "$test" | head -1 | sed 's/.*trace_//')
  [ -n "$ident" ] || die "$test names no @sfreplay.trace_…"
  trace=""
  for t in e2e/traces/*.trace; do
    b=$(basename "$t" .trace)
    [ "$(printf '%s' "$b" | tr -c 'a-z0-9\n' '_')" = "$ident" ] && trace=$t
  done
  [ -n "$trace" ] || die "no e2e/traces/*.trace for trace_$ident"
  # its mark: the six digits the test's words and its trace share most; its station's directory as the trace has it
  t=$(python3 - "$test" "$trace" <<'PY'
import re, sys, collections
words = open(sys.argv[1], encoding="utf-8").read()
trace = open(sys.argv[2], encoding="utf-8").read()
c = collections.Counter(m for m in re.findall(r"(?<!\d)(\d{6})(?!\d)", trace) if m in words)
print(c.most_common(1)[0][0] if c else "")
PY
)
  s=$(grep -o '/tmp/mb[A-Za-z0-9-]*' "$trace" | sort | uniq -c | sort -rn | awk 'NR==1 {print $2}')
  [ -n "$t" ] || die "$n: no mark of its run found in $test and $trace"
  [ -z "$tag" ] || [ "$tag" = "$t" ] || die "$n was recorded with the mark $t, the others before it $tag: rerecord them apart"
  tag=$t; [ -n "$s" ] && station=$s
  echo "rerecord: $n ← $test (trace $trace, mark $t${s:+, station $s})"
  FLOW_EMIT="$TMP/$idx-$n.drive" moon test --target js "$test" > "$TMP/$idx-$n.test.log" 2>&1
  [ -s "$TMP/$idx-$n.drive" ] || { grep -a 'Error\]\|error:\|failed\|^flow:' "$TMP/$idx-$n.test.log" | head -20 | cut -c1-300; die "$test wrote no script"; }
  tests="$tests $idx-$n:$trace:$test"
done
[ -n "$tag" ] || die "no test among: $*"
echo "rerecord: the scripts written ($TMP)"; ls "$TMP"/*.drive | sed 's/^/  /'
# (each step once the app is settled, as the Tester's steps are taken: what came of the last one in, its page loaded;
# until drive's named events take its place)
export E2E_STATION=${station:-${E2E_STATION:-}} E2E_TAG=$tag E2E_FLOWS=$TMP MBUI_CORE_TRACE=1 MBUI_DRIVE_SETTLED=1
[ -n "$E2E_STATION" ] || unset E2E_STATION
bash scripts/e2e-local.sh down > /dev/null 2>&1
bash scripts/e2e-local.sh up > "$TMP/up.log" 2>&1 || { tail -30 "$TMP/up.log"; die "the local still.fail did not come up"; }
bash e2e/run.sh mac 2>&1 | tee "$TMP/run.log" | grep -a '^PASS\|^FAIL\|flows passed\|DRIVE FAIL'
rc=${PIPESTATUS[0]}
[ -n "${E2E_KEEP:-}" ] || bash scripts/e2e-local.sh down > /dev/null 2>&1
[ $rc = 0 ] || die "the run failed: the traces are left as they were ($TMP/run.log, out/e2e/mac/)"
code=0
for x in $tests; do
  name=${x%%:*}; rest=${x#*:}; trace=${rest%%:*}; test=${rest#*:}
  cp "$trace" "$TMP/$(basename "$trace").old"
  python3 scripts/trace.py "out/e2e/mac/$name.log" "$(basename "$trace" .trace)"
  python3 scripts/tracediff.py "$TMP/$(basename "$trace").old" "$trace" | sed "s|^|  $(basename "$trace" .trace): |"
  if moon test --target js "$test" > "$TMP/$name.after.log" 2>&1; then echo "  $test: passes"; else
    echo "  $test: fails over the new trace ($TMP/$name.after.log):"; grep -a '^flow:\|assert_idle' "$TMP/$name.after.log" | head -5 | cut -c1-300; code=1; fi
done
exit $code
