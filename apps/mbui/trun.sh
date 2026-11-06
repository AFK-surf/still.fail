#!/bin/bash
# Runs each scene test file and the fling tests; every log kept whole in $OUT, each exit code and count reported.
[ -d ../tools ] && export MBUI_TOOLS=$(cd .. && pwd)/tools
. mbui/scripts/env.sh
OUT=${OUT:-../runs/$(date +%s)}
mkdir -p "$OUT"
echo "out $OUT"
echo "head ${HEAD:-unknown} (local worktree; uncommitted: ${DIRTY:-?})"
for f in mbui/src/ui/scene_layers.mbt mbui/src/ui/scene_segs.mbt mbui/src/ui/view_host.mbt src/sfapp/home_fling_wbtest.mbt; do
  echo "sha256 $(shasum -a 256 $f)"
done
fails=0
FILES="src/ui/scene_segs_wbtest.mbt src/ui/own_only_kept_wbtest.mbt src/ui/scene_check_pieces_wbtest.mbt src/ui/nested_places_wbtest.mbt src/ui/scene_raised_shapes_wbtest.mbt src/ui/scene_left_out_wbtest.mbt src/ui/clip_wbtest.mbt src/ui/scene_tops_wbtest.mbt src/ui/handle_wbtest.mbt src/ui/tree_shapes_wbtest.mbt src/ui/scene_owners_wbtest.mbt src/ui/scene_cost_wbtest.mbt src/view/own_only_wbtest.mbt"
for f in $FILES; do
  log="$OUT/$(basename $f .mbt).log"
  (cd mbui && moon test --target native $f > "../$log" 2>&1); code=$?
  total=$(grep -a "^Total tests" "$log" | tail -1)
  echo "$f exit=$code ${total:-NO TOTAL LINE}"
  if [ $code -ne 0 ] || [ -z "$total" ] || ! echo "$total" | grep -q "failed: 0"; then fails=$((fails + 1)); fi
  if [ $code -ne 0 ]; then grep -a "FAILED\|abort\|differs\|Error" "$log" | grep -v Warning | head -3 | cut -c1-600; fi
done
log="$OUT/home_fling.log"
moon test --target native -p stillfail/sfapp --filter "the chats' list flung on a phone*" > "$log" 2>&1; code=$?
echo "home fling exit=$code $(grep -a '^Total tests' $log | tail -1) (two known failures: whole-frame and drawn-again asserts)"
# (the two known: the whole-frame assert at line 32, the drawn-again assert at line 88; any other failing test is new)
known=$(grep -a "^\[stillfail\] test sfapp/home_fling_wbtest.mbt" "$log" | grep -c "home_fling_wbtest.mbt:32:\|home_fling_wbtest.mbt:88:")
all=$(grep -a -c "^\[stillfail\] test .* failed" "$log")
echo "home fling failures: $all, of them the two known: $known"
if [ "$all" != "$known" ] || ! grep -a -q "^Total tests: 2," "$log"; then fails=$((fails + 1)); fi
grep -a "scene check:\|^frames:\|differs from the frame drawn\|the scene kept" "$log" | head -4 | cut -c1-600
grep -a -o "drawn again: [a-z ,:'A-Z]*" "$log" | sort | uniq -c
echo "files failing (beyond the two known): $fails"
[ $fails -eq 0 ]
