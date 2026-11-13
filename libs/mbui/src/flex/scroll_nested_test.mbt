// What scrolls (overflow: scroll) holds what it holds as tall as that is, whatever room it has, its own height bound as
// ever: a column 100 tall scrolling, holding 150, then a column 100 tall scrolling (giving way, down to nothing, where
// it is short of room) holding 400, then 400.

///|
test "scroll in scroll: the inner as tall as it is said, what the outer holds as tall as all of it" {
  let root = @flex.Node::new()
  root.style.position = Absolute
  root.style.set_width(Pt(300.0))
  root.style.set_height(Pt(844.0))
  let outer = @flex.Node::new()
  outer.style.set_height(Pt(100.0))
  outer.style.overflow = Scroll
  root.add(outer)
  let held = @flex.Node::new()
  held.style.shrink = 0.0
  outer.add(held)
  let above = @flex.Node::new()
  above.style.set_height(Pt(150.0))
  held.add(above)
  let inner = @flex.Node::new()
  inner.style.set_height(Pt(100.0))
  inner.style.shrink = 1.0
  inner.style.set_min_height(Pt(0.0))
  inner.style.overflow = Scroll
  held.add(inner)
  let inner_held = @flex.Node::new()
  inner_held.style.shrink = 0.0
  inner.add(inner_held)
  let rows = @flex.Node::new()
  rows.style.set_height(Pt(400.0))
  inner_held.add(rows)
  let below = @flex.Node::new()
  below.style.set_height(Pt(400.0))
  held.add(below)
  @flex.compute(root)
  check("outer", outer, 0.0, 0.0, 300.0, 100.0)
  check("held", held, 0.0, 0.0, 300.0, 650.0)
  check("inner", inner, 0.0, 150.0, 300.0, 100.0)
  check("inner_held", inner_held, 0.0, 0.0, 300.0, 400.0)
  check("below", below, 0.0, 250.0, 300.0, 400.0)
}

///|
test "scroll in scroll: the same with no scrolling said: what the outer holds kept to its room, the inner giving way" {
  let root = @flex.Node::new()
  root.style.position = Absolute
  root.style.set_width(Pt(300.0))
  root.style.set_height(Pt(844.0))
  let outer = @flex.Node::new()
  outer.style.set_height(Pt(100.0))
  root.add(outer)
  let held = @flex.Node::new()
  held.style.shrink = 0.0
  outer.add(held)
  let above = @flex.Node::new()
  above.style.set_height(Pt(150.0))
  held.add(above)
  let inner = @flex.Node::new()
  inner.style.set_height(Pt(100.0))
  inner.style.shrink = 1.0
  inner.style.set_min_height(Pt(0.0))
  held.add(inner)
  @flex.compute(root)
  // (what it was before: kept so for what does not scroll)
  check("inner", inner, 0.0, 150.0, 300.0, 0.0)
}
