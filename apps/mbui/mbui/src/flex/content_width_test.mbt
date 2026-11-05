///|
test "allocated content width resolves percentage padding against the containing block" {
  let root = @flex.Node::new()
  let list = @flex.Node::new()
  list.style.set_width(Pt(300.0))
  list.style.set_height(Pt(80.0))
  list.style.set_padding_left(Pct(10.0))
  list.style.set_padding_right(Pct(10.0))
  root.add(list)
  let row = @flex.Node::new()
  row.style.set_height(Pt(40.0))
  list.add(row)
  for width in [400.0, 500.0] {
    @flex.compute(root, width~, height=100.0, round=false, reuse=true)
    let expected = 300.0 - width * 0.2
    assert_eq(row.width, expected)
    assert_eq(@flex.content_width(list, list.width), expected)
  }
}
