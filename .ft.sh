# .ft.sh : the anchored list's tests and the tests of what it touches (view: the anchored list's, the scroll's), each
# with its exit code and count, the sources' hashes; exits non-zero where any run failed, ran no test, or is missing
# (a file not at this base said skipped where it is not asked for by FILES)
set -u
export MBUI_TOOLS="$HOME/.local/share/mbui-tools/current"; export PATH="$MBUI_TOOLS/moon/bin:$HOME/.moon/bin:$PATH"
O=$PWD/ft_out; mkdir -p $O; cd apps/mbui/mbui
for f in src/view/list_anchor.mbt src/view/list_anchor_flip_test.mbt src/view/list_anchor_flip_wbtest.mbt src/view/list_anchor_test.mbt src/view/list_anchor_foot_test.mbt src/view/scroll_list.mbt src/view/scroll.mbt; do
  [ -f $f ] && shasum $f || echo "absent $f"
done > $O/hashes.txt
asked=${FILES:-}
bad=0
for f in ${FILES:-list_anchor_flip_test list_anchor_flip_wbtest list_anchor_foot_test list_anchor_test list_anchor_to_end_test list_anchor_indexed_test scroll_test scroll_let_go_test scroll_across_test laid_passes_test}; do
  if [ ! -f src/view/$f.mbt ]; then
    if [ -n "$asked" ]; then echo "$f: MISSING (asked for)"; bad=1; else echo "$f: skipped (not at this base)"; fi
    continue
  fi
  moon test --target wasm-gc src/view/$f.mbt > $O/$f.log 2>&1; rc=$?
  total=$(grep -a 'Total tests' $O/$f.log | tail -1)
  echo "$f rc=$rc $total"
  [ $rc = 0 ] || { bad=1; grep -a "failed:" $O/$f.log | cut -c1-500 | head -4; }
  case "$total" in *"Total tests: 0,"*|"") echo "$f: NO TESTS RAN"; bad=1;; esac
done
echo "overall rc=$bad"
exit $bad
