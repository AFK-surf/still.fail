// The ring that says how far as a node (progress_ring_node) drawn as the old view's progress_ring is: its track and
// its part, at each part it is told; told another, nothing of it made again.

///|
let ring_test_size : Double = 14.0

///|
/// How far the node is from the old one, along the row.
let ring_test_apart : Double = 300.0

///|
/// The ring as an old view draws it at (0, 0) and as a node 300 in, both showing `part` as it changes.
fn ring_pair(part : @signals.Signal[Double]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=600.0, h=100.0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(ring_test_size))).height(Is(Some(ring_test_size))) |> ignore
      @ui.old(h, fn(c) { progress_ring(c, ring_test_size, part.get(), white) |> ignore }).grow(Is(1.0)) |> ignore
    })
    |> ignore
    root.box(fn(g) { g.width(Is(Some(ring_test_apart - ring_test_size))) |> ignore }) |> ignore
    progress_ring_node(root, ring_test_size, fn() { part.get() }, fn() { white }) |> ignore
  })
  t.draw()
  t
}

///|
/// The shapes' bands drawn on either side (the old view's, the node's), each where it is from its ring's left.
fn ring_drawn(t : @ui.Tester) -> (Array[(Double, Double, Double, Double, Double, Int64)], Array[(Double, Double, Double, Double, Double, Int64)]) {
  let old = []
  let new = []
  for s in t.drawn_shapes() {
    if s.0 < ring_test_apart / 2.0 {
      old.push(s)
    } else {
      new.push((s.0 - ring_test_apart, s.1, s.2, s.3, s.4, s.5))
    }
  }
  (old, new)
}

///|
/// Whether two rings' bands are drawn alike (each number to the last few digits of a double: 300 taken off).
fn ring_alike(
  a : Array[(Double, Double, Double, Double, Double, Int64)],
  b : Array[(Double, Double, Double, Double, Double, Int64)],
) -> Bool {
  let near = fn(x : Double, y : Double) { (x - y).abs() <= 1.0e-9 }
  a.length() == b.length() &&
  a
  .iter()
  .zip(b.iter())
  .all(fn(p) {
    near(p.0.0, p.1.0) && near(p.0.1, p.1.1) && near(p.0.2, p.1.2) && near(p.0.3, p.1.3) && near(p.0.4, p.1.4) && p.0.5 == p.1.5
  })
}

///|
test "the ring as a node drawn as the old view's progress_ring is, none come, a part, all of it and past it; told another part, nothing of it made again" {
  let part = @signals.signal(0.0)
  let t = ring_pair(part)
  let alive = @ui.view_tree().unwrap().alive()
  let seen = []
  for p in [0.0, 0.35, 1.0, 1.5] {
    part.set(p)
    t.frame()
    let (old, new) = ring_drawn(t)
    assert_true(old.length() > 0, msg="at \{p}")
    assert_true(ring_alike(new, old), msg="at \{p}: old \{old.length()}, node \{new.length()}")
    seen.push(new.length())
  }
  // (more of it drawn as more is come: the track alone, then the track and its part)
  assert_true(seen[1] > seen[0], msg="\{Repr(seen)}")
  // (its nodes the same: told another part, only what it draws worked out again)
  assert_eq(@ui.view_tree().unwrap().alive(), alive)
  assert_eq(t.audit(), [])
}
