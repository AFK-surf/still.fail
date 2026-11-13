// Style's stretch_past_max (not CSS's): an item's max-height bounds the height it asks of its row, not the height its
// row stretches it to.

///|
/// A row 300 wide, as tall as what it holds: a column at most 50 high holding 200 (`past`: stretch_past_max), and beside
/// it one `beside` high. The row and the two items.
fn past_max_row(past : Bool, beside : Double) -> (@flex.Node, @flex.Node, @flex.Node) {
  let root = @flex.Node::new()
  root.style.position = Absolute
  root.style.direction = Row
  root.style.set_width(Pt(300.0))
  let held = @flex.Node::new()
  held.style.set_width(Pt(100.0))
  held.style.set_max_height(Pt(50.0))
  held.style.stretch_past_max = past
  let tall = @flex.Node::new()
  tall.style.set_height(Pt(200.0))
  held.add(tall)
  root.add(held)
  let other = @flex.Node::new()
  other.style.set_width(Pt(100.0))
  other.style.set_height(Pt(beside))
  root.add(other)
  @flex.compute(root)
  (root, held, other)
}

///|
test "stretch_past_max: the row as tall as the taller beside it, the held one stretched past its most to it" {
  let (root, held, _) = past_max_row(true, 120.0)
  check("root", root, 0.0, 0.0, 300.0, 120.0)
  check("held", held, 0.0, 0.0, 100.0, 120.0)
}

///|
test "stretch_past_max: the one beside it shorter, the row as tall as the held one asks, its most" {
  let (root, held, _) = past_max_row(true, 30.0)
  check("root", root, 0.0, 0.0, 300.0, 50.0)
  check("held", held, 0.0, 0.0, 100.0, 50.0)
}

///|
test "without it, as CSS: stretched no further than its most" {
  let (root, held, _) = past_max_row(false, 120.0)
  check("root", root, 0.0, 0.0, 300.0, 120.0)
  check("held", held, 0.0, 0.0, 100.0, 50.0)
}
