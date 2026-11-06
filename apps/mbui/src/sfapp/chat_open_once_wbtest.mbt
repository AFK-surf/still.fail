// A long chat opened on a phone: each frame from the tap on laid out once (the tree's whole layouts a frame, not each
// node's measures in one), its composer made with its page (not a flush later) and its room given its list by the
// page's layout as it measures it (no room read back and laid out again: the rows not moved up after it).

///|
test "a long chat opened on a phone: every frame of its opening laid out once" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="long", w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms * 2.0)
  let title = "把旧的截图都换成新的"
  let (x, y) = t.find(title).unwrap()
  let tree = @ui.view_tree().unwrap()
  let computes : Array[Int] = []
  let was = Ref(tree.work().computes)
  t.each_frame(Some(fn() {
    let now = tree.work().computes
    computes.push(now - was.val)
    was.val = now
  }))
  t.tap(x, y)
  t.run_for(@ui.move_most_ms * 2.0)
  t.each_frame(None)
  // (its frames taken, the first of them laid out: the tree's whole layouts, each frame's count of them (Tree::work's
  // computes: a whole layout of the root, not each node's measures in it))
  assert_true(computes.length() > 0 && computes[0] == 1, msg="layouts in each frame: \{computes}")
  assert_true(computes.iter().all(fn(n) { n <= 1 }), msg="layouts in each frame: \{computes}")
}
