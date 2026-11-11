// One laid out over the rest (Absolute) laid out nowhere (DisplayNone), then in again: laid out where it was, not left
// out (Node::left_out) as it was while it was nowhere: what reads that (mbui's view) draws it again.

///|
test "absolute, laid out nowhere then in again: not left out, laid out as it was" {
  for reuse in [false, true] {
    let root = @flex.Node::new()
    root.style.set_width(Pt(100.0))
    root.style.set_height(Pt(100.0))
    let over = @flex.Node::new()
    over.style.position = Absolute
    over.style.set_width(Pt(20.0))
    over.style.set_height(Pt(30.0))
    root.add(over)
    @flex.compute(root, round=!reuse, reuse~)
    check("over", over, 0.0, 0.0, 20.0, 30.0)
    assert_false(over.left_out(), msg="in")
    over.style.display = DisplayNone
    over.dirty = true
    root.dirty = true
    @flex.compute(root, round=!reuse, reuse~)
    check("over, nowhere", over, 0.0, 0.0, 0.0, 0.0)
    assert_true(over.left_out(), msg="nowhere")
    over.style.display = Flex
    over.dirty = true
    root.dirty = true
    @flex.compute(root, round=!reuse, reuse~)
    check("over, in again", over, 0.0, 0.0, 20.0, 30.0)
    assert_false(over.left_out(), msg="in again (reuse \{reuse})")
  }
}
