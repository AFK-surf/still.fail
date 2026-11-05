// What a compute kept for its root's tree found again by its next compute on the same grid, another tree computed on
// another grid between (an old view's on a device's whole pixels, the window's tree on none: every frame on Android).

///|
fn grid_tree(measured : Ref[Int]) -> @flex.Node {
  let root = @flex.Node::new()
  root.style.set_width(Pt(300.0))
  root.style.set_height(Pt(300.0))
  let words = @flex.Node::new()
  words.measure = Some(fn(w, _, _, _) {
    measured.val += 1
    (if w.is_nan() { 120.0 } else { w.min(120.0) }, 20.0)
  })
  root.add(words)
  root
}

///|
test "a tree computed again on its grid, another computed on another between: what it kept found again" {
  let measured = Ref(0)
  let window = grid_tree(measured)
  let other = @flex.Node::new()
  other.style.set_width(Pt(100.0))
  other.style.set_height(Pt(100.0))
  @flex.compute(window, width=300.0, height=300.0, round=false, reuse=true)
  let once = measured.val
  @flex.compute(other, width=100.0, height=100.0, round=false, reuse=true, grid=3.25)
  @flex.compute(window, width=300.0, height=300.0, round=false, reuse=true)
  assert_eq(measured.val, once)
}

///|
test "the same tree computed on another grid: nothing it kept found" {
  let measured = Ref(0)
  let window = grid_tree(measured)
  @flex.compute(window, width=300.0, height=300.0, round=false, reuse=true)
  let once = measured.val
  @flex.compute(window, width=300.0, height=300.0, round=false, reuse=true, grid=3.25)
  assert_true(measured.val > once)
}
