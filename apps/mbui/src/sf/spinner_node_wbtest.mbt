// The spinner as a node of the window's tree (spinner_node) drawn as the old view's spinner is (spinner): the same ring
// and arc, turned as far at each moment; turning, nothing of it made again.

///|
/// The spinner as an old view draws it at (0, 0) and as a node 300 in, both 14 across.
fn spinner_pair() -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=600.0, h=100.0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(14.0))).height(Is(Some(14.0))) |> ignore
      @ui.old(h, fn(c) { spinner(c) |> ignore }).grow(Is(1.0)) |> ignore
    })
    |> ignore
    root.box(fn(g) { g.width(Is(Some(286.0))) |> ignore }) |> ignore
    spinner_node(root) |> ignore
  })
  t.draw()
  t
}

///|
/// The pieces of lines drawn on either side (the old view's, the node's), each where it is from its spinner's left (its
/// place, size, ends, colour, how far it is turned and about where).
fn spinner_drawn(t : @ui.Tester) -> (Array[Array[Double]], Array[Array[Double]]) {
  let old = []
  let new = []
  for i in t.drawn_instances() {
    if i[5] != 10.0 {
      continue
    }
    let dx = if i[0] < 150.0 { 0.0 } else { 300.0 }
    let piece = [i[0] - dx, i[1], i[2], i[3], i[4], i[8], i[9], i[10], i[11], i[12], i[13], i[14], i[15], i[32], i[33] - dx, i[34]]
    if dx == 0.0 {
      old.push(piece)
    } else {
      new.push(piece)
    }
  }
  (old, new)
}

///|
/// Whether two spinners' pieces are drawn alike: each number the same to the last few digits of a double (the old one's
/// place added on in another order, 300 taken off).
fn spinner_alike(a : Array[Array[Double]], b : Array[Array[Double]]) -> Bool {
  a.length() == b.length() &&
  a
  .iter()
  .zip(b.iter())
  .all(fn(p) { p.0.length() == p.1.length() && p.0.iter().zip(p.1.iter()).all(fn(v) { (v.0 - v.1).abs() <= 1.0e-9 }) })
}

///|
test "the spinner as a node drawn as the old view's spinner is, at its first frame and turned a while on (turned as far, about the same point); turning, nothing of it made again" {
  let t = spinner_pair()
  let (old0, new0) = spinner_drawn(t)
  let made = @ui.view_painted().made
  t.frame_at(t.time() + 300.0)
  let (old1, new1) = spinner_drawn(t)
  // (the point turned about, said apart: the middle of what the old one's pieces cover, a hair off its ring's)
  let about = fn(ps : Array[Array[Double]]) { ps.map(fn(p) { [p[14], p[15]] }) }
  assert_eq(
    (
      spinner_alike(new0, old0),
      spinner_alike(new1, old1),
      spinner_alike(about(new1), about(old1)),
      about(new1).iter().all(fn(p) { (p[0] - 7.0).abs() > 0.01 }),
      new1 != new0,
      old0.length() > 0,
      @ui.view_painted().made - made,
    ),
    (true, true, true, true, true, true, 0),
    msg="old \{about(old1)[:1]}, node \{about(new1)[:1]}",
  )
}
