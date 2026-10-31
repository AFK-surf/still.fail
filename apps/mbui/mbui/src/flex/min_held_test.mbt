// Style's min_held (not CSS's): an item of a row never narrower than what it holds needs, whatever its basis and
// min-width say; what is beside it gives way first.

///|
/// A row `w` wide holding two that share it alike (basis 0, growing alike), the second holding a row of parts 40 wide
/// each, 8 apart, `parts` of them (`held`: min_held, the second never narrower than they are), its min-width 0 as a
/// basis of 0's would leave it. The two items.
fn held_row(w : Double, parts : Int, held : Bool) -> (@flex.Node, @flex.Node) {
  let root = @flex.Node::new()
  root.style.position = Absolute
  root.style.direction = Row
  root.style.set_width(Pt(w))
  root.style.set_height(Pt(40.0))
  let a = @flex.Node::new()
  a.style.set_basis(Pt(0.0))
  a.style.grow = 1.0
  a.style.shrink = 1.0
  a.style.set_min_width(Pt(0.0))
  let b = @flex.Node::new()
  b.style.set_basis(Pt(0.0))
  b.style.grow = 1.0
  b.style.shrink = 1.0
  b.style.set_min_width(Pt(0.0))
  b.style.min_held = held
  let tools = @flex.Node::new()
  tools.style.direction = Row
  tools.style.set_gap_col(Pt(8.0))
  for _ in 0..<parts {
    let p = @flex.Node::new()
    p.style.set_width(Pt(40.0))
    p.style.set_height(Pt(40.0))
    tools.add(p)
  }
  b.add(tools)
  root.add(a)
  root.add(b)
  @flex.compute(root)
  (a, b)
}

///|
test "min_held: room enough, the two alike, as their basis says" {
  let (a, b) = held_row(400.0, 3, true)
  check("a", a, 0.0, 0.0, 200.0, 40.0)
  check("b", b, 200.0, 0.0, 200.0, 40.0)
}

///|
test "min_held: what it holds wider than its share, it as wide as that, the one beside it giving way; not so said, as wide as its share" {
  // (5 parts: 5 × 40 + 4 × 8 = 232, more than 300's half)
  let (a, b) = held_row(300.0, 5, true)
  check("a", a, 0.0, 0.0, 68.0, 40.0)
  check("b", b, 68.0, 0.0, 232.0, 40.0)
  let (a, b) = held_row(300.0, 5, false)
  check("a", a, 0.0, 0.0, 150.0, 40.0)
  check("b", b, 150.0, 0.0, 150.0, 40.0)
}
