// compute(reuse=true) against a fresh compute: random trees, changed a
// little at a time (a style, a text, children added, removed, moved, the
// space offered), marked dirty as a caller must, and laid out again; every
// node must come out where a fresh copy of the tree puts it.

///|
struct Rng {
  mut s : UInt
}

///|
fn Rng::next(self : Rng) -> Int {
  self.s = self.s * 1664525U + 1013904223U
  (self.s >> 8).reinterpret_as_int()
}

///|
fn Rng::below(self : Rng, n : Int) -> Int {
  self.next() % n
}

///|
fn Rng::chance(self : Rng, pct : Int) -> Bool {
  self.below(100) < pct
}

///|
/// A fresh copy of the tree, nothing cached.
fn fresh(n : @flex.Node) -> @flex.Node {
  let c = @flex.Node::new()
  let s = n.style
  c.style.display = s.display
  c.style.position = s.position
  c.style.direction = s.direction
  c.style.wrap = s.wrap
  c.style.justify = s.justify
  c.style.align_items = s.align_items
  c.style.align_self = s.align_self
  c.style.align_content = s.align_content
  c.style.grow = s.grow
  c.style.shrink = s.shrink
  c.style.set_basis(s.get_basis())
  c.style.set_width(s.get_width())
  c.style.set_height(s.get_height())
  c.style.set_min_width(s.get_min_width())
  c.style.set_min_height(s.get_min_height())
  c.style.set_max_width(s.get_max_width())
  c.style.set_max_height(s.get_max_height())
  c.style.set_margin_left(s.get_margin_left())
  c.style.set_margin_top(s.get_margin_top())
  c.style.set_margin_right(s.get_margin_right())
  c.style.set_margin_bottom(s.get_margin_bottom())
  c.style.set_padding_left(s.get_padding_left())
  c.style.set_padding_top(s.get_padding_top())
  c.style.set_padding_right(s.get_padding_right())
  c.style.set_padding_bottom(s.get_padding_bottom())
  c.style.set_border_left(s.get_border_left())
  c.style.set_border_top(s.get_border_top())
  c.style.set_border_right(s.get_border_right())
  c.style.set_border_bottom(s.get_border_bottom())
  c.style.set_inset_left(s.get_inset_left())
  c.style.set_inset_top(s.get_inset_top())
  c.style.set_inset_right(s.get_inset_right())
  c.style.set_inset_bottom(s.get_inset_bottom())
  c.style.set_gap_row(s.get_gap_row())
  c.style.set_gap_col(s.get_gap_col())
  c.style.aspect = s.aspect
  c.style.set_box_sizing(s.get_box_sizing())
  c.style.overflow = s.overflow
  c.measure = n.measure
  for k in n.children {
    c.add(fresh(k))
  }
  c
}

///|
fn text_of(len : Int) -> @flex.MeasureFn {
  let full = len.to_double() * 7.0
  fn(width, wm, _h, _hm) {
    let w = match wm {
      Exactly => width
      AtMost => if width < full { width } else { full }
      Undefined => full
    }
    let lines = if w > 0.0 { (full / w).ceil() } else { 1.0 }
    (w, lines * 18.0)
  }
}

///|
fn rand_dim(r : Rng) -> @flex.Dim {
  match r.below(6) {
    0 => Pt(r.below(120).to_double())
    1 => Pct((r.below(10) * 10).to_double())
    _ => Auto
  }
}

///|
/// Changes one thing of a node's style at random.
fn restyle(r : Rng, n : @flex.Node) -> Unit {
  let s = n.style
  match r.below(19) {
    0 => s.direction = if r.chance(50) { Row } else { Column }
    1 => s.set_width(rand_dim(r))
    2 => s.set_height(rand_dim(r))
    3 => s.grow = r.below(3).to_double()
    4 => s.shrink = r.below(2).to_double()
    5 => s.set_padding_left(Pt(r.below(12).to_double()))
    6 => s.set_padding_top(Pt(r.below(12).to_double()))
    7 => s.set_gap_row(Pt(r.below(8).to_double()))
    8 => s.set_gap_col(Pt(r.below(8).to_double()))
    9 =>
      s.align_items = match r.below(5) {
        0 => FlexStart
        1 => Center
        2 => FlexEnd
        _ => Stretch
      }
    10 =>
      s.justify = match r.below(4) {
        0 => FlexStart
        1 => Center
        2 => SpaceBetween
        _ => FlexEnd
      }
    11 => s.wrap = if r.chance(70) { NoWrap } else { Wrap }
    12 => s.set_basis(if r.chance(50) { Auto } else { Pt(r.below(60).to_double()) })
    13 => {
      s.position = if r.chance(85) { Relative } else { Absolute }
      s.set_inset_left(if r.chance(50) { Auto } else { Pt(r.below(30).to_double()) })
      s.set_inset_top(if r.chance(50) { Auto } else { Pt(r.below(30).to_double()) })
    }
    14 => s.set_max_width(if r.chance(70) { Auto } else { Pt(r.below(200).to_double()) })
    15 =>
      s.align_self = match r.below(5) {
        0 => FlexStart
        1 => Center
        2 => FlexEnd
        3 => Stretch
        _ => Auto
      }
    16 => s.wrap = if r.chance(40) { NoWrap } else { Wrap }
    17 => s.set_padding_left(Pct(r.below(20).to_double()))
    _ => s.set_margin_left(Pt(r.below(10).to_double()))
  }
}

///|
fn rand_node(r : Rng, depth : Int) -> @flex.Node {
  let n = @flex.Node::new()
  for _ in 0..<r.below(4) {
    restyle(r, n)
  }
  if depth >= 3 || r.chance(35) {
    n.measure = Some(text_of(r.below(40)))
  } else {
    for _ in 0..<(1 + r.below(4)) {
      n.add(rand_node(r, depth + 1))
    }
  }
  n
}

///|
/// Every node and its path from the root.
fn all_nodes(n : @flex.Node, path : Array[@flex.Node], out : Array[Array[@flex.Node]]) -> Unit {
  let p = path.copy()
  p.push(n)
  out.push(p)
  for c in n.children {
    all_nodes(c, p, out)
  }
}

///|
fn same_layout(a : @flex.Node, b : @flex.Node, at : String) -> Unit raise {
  let close = fn(x : Double, y : Double) { (x - y).abs() < 1.0e-6 || (x != x && y != y) }
  if !close(a.left, b.left) ||
    !close(a.top, b.top) ||
    !close(a.width, b.width) ||
    !close(a.height, b.height) {
    fail(
      "\{at}: reused \{a.left},\{a.top} \{a.width}x\{a.height}, fresh \{b.left},\{b.top} \{b.width}x\{b.height}",
    )
  }
  if a.children.length() != b.children.length() {
    fail("\{at}: children differ")
  }
  for i, c in a.children {
    if c.style.display != DisplayNone {
      same_layout(c, b.children[i], at + "/" + i.to_string())
    }
  }
}

///|
test "reused layouts are the layouts a fresh tree gets" {
  let r = { s: 12345U }
  let mut reused = 0
  for t in 0..<400 {
    let root = rand_node(r, 0)
    let mut w = (200 + r.below(400)).to_double()
    let mut h = if r.chance(50) { 0.0 / 0.0 } else { (200 + r.below(400)).to_double() }
    @flex.compute(root, width=w, height=h, round=false, reuse=true)
    for step in 0..<12 {
      let nodes : Array[Array[@flex.Node]] = []
      all_nodes(root, [], nodes)
      let path = nodes[r.below(nodes.length())]
      let n = path[path.length() - 1]
      let what = r.below(8)
      if what == 0 {
        // the space offered (or the root's own limit, and what is beside)
        if r.chance(25) {
          root.style.set_max_width(if r.chance(30) { Auto } else { Pt((150 + r.below(300)).to_double()) })
          root.dirty = true
        } else if r.chance(50) {
          w = (150 + r.below(450)).to_double()
        } else {
          h = if r.chance(50) { 0.0 / 0.0 } else { (150 + r.below(450)).to_double() }
        }
      } else if what == 1 && n.measure is Some(_) {
        n.measure = Some(text_of(r.below(40)))
      } else if what == 2 && n.measure is None {
        n.add(rand_node(r, 2))
      } else if what == 3 && n.children.length() > 1 {
        n.children.remove(r.below(n.children.length())) |> ignore
      } else if what == 4 && n.children.length() > 1 {
        n.children.rev_in_place()
      } else if what == 5 && path.length() > 2 {
        // to another parent: both lay out again
        let parent = path[path.length() - 2]
        let k = parent.children.search_by(fn(c) { physical_equal(c, n) }).unwrap()
        if parent.children.length() > 1 {
          parent.children.remove(k) |> ignore
          let to = path[0]
          to.add(n)
        }
      } else if what == 6 {
        // nothing changed at all
        ()
      } else {
        restyle(r, n)
      }
      // what changed and everything above it (path[0] the root, in the
      // moves too)
      if what != 0 && what != 6 {
        for p in path {
          p.dirty = true
        }
      }
      @flex.compute(root, width=w, height=h, round=false, reuse=true)
      if what == 6 || what == 0 {
        reused = reused + 1
      }
      let f = fresh(root)
      @flex.compute(f, width=w, height=h, round=false)
      same_layout(root, f, "tree \{t} step \{step} (\{what})")
    }
  }
  assert_true(reused > 0)
}

///|
test "a tree laid out again as it was is not laid out" {
  let root = @flex.Node::new()
  root.style.direction = Row
  let a = @flex.Node::new()
  a.measure = Some(text_of(10))
  let b = @flex.Node::new()
  b.style.grow = 1.0
  let bc = @flex.Node::new()
  bc.measure = Some(text_of(30))
  b.add(bc)
  root.add(a)
  root.add(b)
  @flex.compute(root, width=300.0, round=false, reuse=true)
  assert_true(root.laid_out())
  assert_true(bc.laid_out())
  let bw = b.width
  @flex.compute(root, width=300.0, round=false, reuse=true)
  assert_false(root.laid_out())
  assert_false(bc.laid_out())
  assert_eq(b.width, bw)
  // the text of a changes: the root and a again, b as it was asked before
  a.measure = Some(text_of(12))
  a.dirty = true
  root.dirty = true
  @flex.compute(root, width=300.0, round=false, reuse=true)
  assert_true(root.laid_out())
  assert_true(a.laid_out())
  assert_true(b.width < bw)
  assert_true(b.laid_out())
  // the space offered changes: all again
  @flex.compute(root, width=320.0, round=false, reuse=true)
  assert_true(root.laid_out())
  // without reuse, always laid out
  @flex.compute(root, width=320.0, round=false)
  assert_true(root.laid_out())
  assert_true(bc.laid_out())
}

///|
/// Lays out `root` with reuse, then a fresh copy, and compares.
fn check_reuse(root : @flex.Node, w : Double, h : Double, at : String) -> Unit raise {
  @flex.compute(root, width=w, height=h, round=false, reuse=true)
  let f = fresh(root)
  @flex.compute(f, width=w, height=h, round=false)
  same_layout(root, f, at)
}

///|
test "reused: a root placed absolutely, offered another width (the space, not the size, changes)" {
  let root = @flex.Node::new()
  root.style.position = Absolute
  let t = @flex.Node::new()
  t.measure = Some(text_of(60))
  root.add(t)
  check_reuse(root, 300.0, 0.0 / 0.0, "300")
  // nothing marked: its known size is the same (none), the room is not
  check_reuse(root, 150.0, 0.0 / 0.0, "150")
  assert_true(t.width <= 150.0)
}

///|
test "reused: a box of fixed width whose padding is a share of its parent's width" {
  let root = @flex.Node::new()
  let b = @flex.Node::new()
  b.style.set_width(Pt(100.0))
  b.style.align_self = FlexStart
  b.style.set_padding_left(Pct(10.0))
  let t = @flex.Node::new()
  t.measure = Some(text_of(5))
  b.add(t)
  root.add(b)
  check_reuse(root, 300.0, 200.0, "300")
  let x = t.left
  // the parent wider: b the same size, what is in it further in
  check_reuse(root, 400.0, 200.0, "400")
  assert_true(t.left > x)
}

///|
test "reused: absolute boxes in absolute boxes" {
  let root = @flex.Node::new()
  let a = @flex.Node::new()
  a.style.position = Absolute
  a.style.set_width(Pt(100.0))
  a.style.set_height(Pt(50.0))
  a.style.set_inset_left(Pt(10.0))
  let b = @flex.Node::new()
  b.style.position = Absolute
  b.style.set_width(Pt(20.0))
  b.style.set_height(Pt(20.0))
  b.style.set_inset_right(Pt(5.0))
  a.add(b)
  root.add(a)
  @flex.compute(root, width=300.0, height=200.0, round=false)
  assert_eq(b.left, 75.0)
  check_reuse(root, 300.0, 200.0, "again")
  a.style.set_width(Pt(120.0))
  a.dirty = true
  root.dirty = true
  check_reuse(root, 300.0, 200.0, "wider")
  assert_eq(b.left, 95.0)
}

///|
/// A row aligned by baseline lays its items out while it is only measured:
/// reuse does not take it.
test "panic reuse refuses items aligned by baseline" {
  let root = @flex.Node::new()
  root.style.direction = Row
  root.style.align_items = Baseline
  let t = @flex.Node::new()
  t.measure = Some(text_of(5))
  root.add(t)
  @flex.compute(root, width=100.0, round=false, reuse=true)
}

///|
/// Absolute boxes under a layout that stands are not placed again.
test "reused: nothing under a kept root is visited" {
  let root = @flex.Node::new()
  let a = @flex.Node::new()
  a.style.position = Absolute
  a.style.set_width(Pt(10.0))
  a.style.set_height(Pt(10.0))
  let b = @flex.Node::new()
  b.measure = Some(text_of(5))
  root.add(a)
  root.add(b)
  @flex.compute(root, width=100.0, height=100.0, round=false, reuse=true)
  let sized = @flex.counters[0]
  let reused = @flex.counters[1]
  @flex.compute(root, width=100.0, height=100.0, round=false, reuse=true)
  // the root's layout stands: one size found (reused), nothing else
  assert_eq(@flex.counters[0], sized)
  assert_eq(@flex.counters[1], reused + 1)
}

///|
/// Rounding works on the layout in place (by absolute edges), so a layout
/// kept from a rounded compute would be rounded twice: with `round`, reuse
/// is off.
test "reused: not with rounding" {
  let root = @flex.Node::new()
  let a = @flex.Node::new()
  a.style.set_height(Pt(10.4))
  let b = @flex.Node::new()
  let c = @flex.Node::new()
  c.style.set_height(Pt(10.5))
  c.style.set_margin_top(Pt(0.5))
  b.add(c)
  root.add(a)
  root.add(b)
  @flex.compute(root, width=100.0, height=100.0, reuse=true)
  a.style.set_height(Pt(10.8))
  a.dirty = true
  root.dirty = true
  @flex.compute(root, width=100.0, height=100.0, reuse=true)
  let f = fresh(root)
  @flex.compute(f, width=100.0, height=100.0)
  same_layout(root, f, "rounded")
}

///|
test "reused: a root placed absolutely, offered another height" {
  let root = @flex.Node::new()
  root.style.position = Absolute
  for _ in 0..<3 {
    let t = @flex.Node::new()
    t.style.set_height(Pt(100.0))
    t.style.shrink = 1.0
    root.add(t)
  }
  check_reuse(root, 100.0, 200.0, "200")
  check_reuse(root, 100.0, 400.0, "400")
  assert_eq(root.children[0].height, 100.0)
}
