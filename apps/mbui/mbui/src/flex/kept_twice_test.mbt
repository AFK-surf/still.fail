// A custom container's child laid out twice in one compute (layout_children, an anchored list's opening row: at its
// own height, then its room's) is no box whose layout was kept from before: what lies over its parts (absolute boxes
// come since) placed with it. One kept from an earlier compute still holds its absolute boxes as placed then.

///|
/// A root 300 × 300 whose own layout lays its one child, `row`, twice as asked (`twice`), 300 wide: the row holds a
/// box 80 × 50, which may hold an absolute box.
fn kept_twice_tree(twice : Ref[Bool]) -> (@flex.Node, @flex.Node, @flex.Node) {
  let root = @flex.Node::new()
  root.style.set_width(Pt(300.0))
  root.style.set_height(Pt(300.0))
  let row = @flex.Node::new()
  let part = @flex.Node::new()
  part.style.set_width(Pt(80.0))
  part.style.set_height(Pt(50.0))
  row.add(part)
  root.add(row)
  root.layout_children = Some(fn(w, _h, _x, _y, _r) {
    @flex.layout_child(row, w) |> ignore
    if twice.val {
      @flex.layout_child(row, w) |> ignore
    }
    row.left = 0.0
    row.top = 0.0
    0.0 / 0.0
  })
  (root, row, part)
}

///|
/// An absolute box 80 × 50 put in `part` and what holds it told it changed.
fn put_over(root : @flex.Node, row : @flex.Node, part : @flex.Node) -> @flex.Node {
  let over = @flex.Node::new()
  over.style.position = Absolute
  over.style.set_width(Pt(80.0))
  over.style.set_height(Pt(50.0))
  part.add(over)
  part.dirty = true
  row.dirty = true
  root.dirty = true
  over
}

///|
test "a child laid out twice in one compute: the absolute box come in it since placed at its size" {
  let twice = Ref(true)
  let (root, row, part) = kept_twice_tree(twice)
  @flex.compute(root, width=300.0, height=300.0, round=false, reuse=true)
  let over = put_over(root, row, part)
  @flex.compute(root, width=300.0, height=300.0, round=false, reuse=true)
  assert_eq((over.width, over.height), (80.0, 50.0))
}

///|
test "a child kept from an earlier compute: its absolute boxes as they were placed, not placed again" {
  let twice = Ref(true)
  let (root, row, part) = kept_twice_tree(twice)
  let over = put_over(root, row, part)
  @flex.compute(root, width=300.0, height=300.0, round=false, reuse=true)
  assert_eq((over.width, over.height), (80.0, 50.0))
  // (its size said otherwise, nothing told it changed: kept, it is not looked at again)
  over.style.set_width(Pt(40.0))
  twice.val = false
  root.dirty = true
  @flex.compute(root, width=300.0, height=300.0, round=false, reuse=true)
  assert_eq(over.width, 80.0)
}
