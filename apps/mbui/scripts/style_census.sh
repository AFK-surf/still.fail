#!/bin/bash
# How many values of each kind still.fail's screens use (src/sfapp/style_census_wbtest.mbt: mbui's Tester::census over
# the fixtures' screens, narrow and wide, light and dark): sizes of words with their lines, weights, paddings and
# gaps, corners, colours. The styles' migration (mbui's docs/style.md) brings each count down; the test's snapshot
# is the counts, updated (UPDATE=1) in the commit that lowers them.
#   apps/mbui/scripts/style_census.sh          the counts, then each kind's values
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
out=$(moon_test_native src/sfapp/style_census_wbtest.mbt ${UPDATE:+--update} 2>&1)
code=$?
echo "$out" | sed -n 's/^census \([a-z]*\) \([0-9]*\): .*/\1 \2/p'
echo
echo "$out" | sed -n 's/^census //p'
echo "$out" | grep -a "failed\|Total tests" | tail -3
exit $code
