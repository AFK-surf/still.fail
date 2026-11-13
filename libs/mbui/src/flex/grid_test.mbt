///|
/// A picture centred in a box that leaves it an odd number of device pixels (at a phone's 3.25 a point, 30 × 59 in
/// 325 × 78): on that grid, a whole pixel from the box's corner, half up, as Compose places it; with none, half way
/// (Yoga's). Laid out on another grid, it is on that one, nothing kept of the last.
test "a centred box on a grid of device pixels: a whole pixel from its parent, half up" {
  let px = fn(v : Double, g : Double) { (v * g * 1000.0).round() / 1000.0 }
  let root = @flex.Node::new()
  root.style.position = Absolute
  root.style.set_width(Pt(100.0))
  root.style.set_height(Pt(78.0 / 3.25))
  root.style.justify = Center
  root.style.align_items = Center
  let pic = @flex.Node::new()
  pic.style.set_width(Pt(30.0 / 3.25))
  pic.style.set_height(Pt(59.0 / 3.25))
  root.add(pic)
  @flex.compute(root, round=false, reuse=true)
  assert_eq((px(pic.left, 3.25), px(pic.top, 3.25)), (147.5, 9.5))
  @flex.compute(root, round=false, reuse=true, grid=3.25)
  assert_eq((px(pic.left, 3.25), px(pic.top, 3.25)), (148.0, 10.0))
  // 262.5 × 63 at 2.625, the picture 24.231 × 47.654: 119.135 and 7.673 over it
  @flex.compute(root, round=false, reuse=true, grid=2.625)
  assert_eq((px(pic.left, 2.625), px(pic.top, 2.625)), (119.0, 8.0))
  @flex.compute(root, round=false, reuse=true, grid=2.625)
  assert_eq((px(pic.left, 2.625), px(pic.top, 2.625)), (119.0, 8.0))
}

///|
/// Placed absolutely, by its static place (centred) and from its parent's far edge: on the grid as well.
test "an absolutely placed box on a grid of device pixels: its static place and its insets on whole pixels" {
  let px = fn(v : Double) { (v * 3.25 * 1000.0).round() / 1000.0 }
  let root = @flex.Node::new()
  root.style.position = Absolute
  root.style.set_width(Pt(100.0))
  root.style.set_height(Pt(78.0 / 3.25))
  root.style.justify = Center
  root.style.align_items = Center
  let mid = @flex.Node::new()
  mid.style.position = Absolute
  mid.style.set_width(Pt(30.0 / 3.25))
  mid.style.set_height(Pt(59.0 / 3.25))
  root.add(mid)
  let corner = @flex.Node::new()
  corner.style.position = Absolute
  corner.style.set_inset_right(Pt(0.0))
  corner.style.set_inset_bottom(Pt(0.0))
  corner.style.set_width(Pt(3.0))
  corner.style.set_height(Pt(3.0))
  root.add(corner)
  @flex.compute(root, round=false, grid=3.25)
  assert_eq((px(mid.left), px(mid.top)), (148.0, 10.0))
  // 9.75 pixels a side, from 325 × 78: at 315.25 and 68.25
  assert_eq((px(corner.left), px(corner.top)), (315.0, 68.0))
}
