// A box that lays out its own children (layout_children, a list's rows made as they come in its window) with none in it
// yet, its size given by what holds it: laid out as any such box is, in a compute that keeps nothing from before (one
// rounded to a screen's pixels) as in one that does.

///|
fn empty_custom_tree(laid : Ref[Int]) -> @flex.Node {
  let root = @flex.Node::new()
  root.style.set_width(Pt(300.0))
  root.style.set_height(Pt(300.0))
  let held = @flex.Node::new()
  held.style.set_width(Pt(300.0))
  held.style.set_height(Pt(300.0))
  held.layout_children = Some(fn(_w, _h, _x, _y, _r) {
    laid.val += 1
    0.0 / 0.0
  })
  root.add(held)
  root
}

///|
test "a box laying out its own children, none in it yet, its size given: laid out in a compute rounded to pixels" {
  let laid = Ref(0)
  @flex.compute(empty_custom_tree(laid), width=300.0, height=300.0)
  assert_eq(laid.val, 1)
}

///|
test "the same, in a compute that keeps what it can" {
  let laid = Ref(0)
  @flex.compute(empty_custom_tree(laid), width=300.0, height=300.0, round=false, reuse=true)
  assert_eq(laid.val, 1)
}
