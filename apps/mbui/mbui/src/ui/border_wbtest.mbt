// A box's border is its own edge: drawn over what it holds (after it), so what reaches the edge never covers it (CSS's
// border is outside what a box holds; here it takes no room). With nothing in it, it is drawn with its ground.

///|
/// The instances of the last frame that are a box's ground or border: (x, y, w, h, its ground's colour's alpha, its
/// border's width), in the order drawn.
fn grounds() -> Array[(Double, Double, Double, Double, Double, Double)] {
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 0.0 {
      out.push((c.inst[b], c.inst[b + 1], c.inst[b + 2], c.inst[b + 3], c.inst[b + 11], c.inst[b + 6]))
    }
  }
  out
}

///|
test "a box's border is drawn over what it holds, its ground inside it" {
  let t = Tester::new(
    fn(c) {
      c.box(w=Px(100.0), h=Px(40.0), bg=0xFFFFFFFFL, border=1.0, border_color=0xD2D2D7FFL, radius=8.0, clip=true, fn() {
        // reaching its every edge, on a ground of its own
        c.box(w=Fill(1.0), h=Fill(1.0), bg=0x2233AAFFL, fn() {  }) |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=100.0,
  )
  ignore(t)
  let gs = grounds()
  // its ground (stopping at the border's inside: its band as wide, in no colour), what it holds, then its border alone
  // (no ground), over what is behind the box rather than over its ground (a see-through border reads so)
  assert_eq(gs.length(), 3)
  assert_eq(gs[0], (0.0, 0.0, 100.0, 40.0, 1.0, 1.0))
  let c = g()
  let first = (0).until(c.ninst).iter().find_first(fn(k) { c.inst[k * inst_size + 5] == 0.0 }).unwrap()
  assert_eq(c.inst[first * inst_size + 15], 0.0)
  assert_eq(gs[1], (0.0, 0.0, 100.0, 40.0, 1.0, 0.0))
  assert_eq(gs[2].5, 1.0)
  assert_eq(gs[2].4, 0.0)
}

///|
test "a clipping box with a border cuts what it holds at its edge, under the border, its corners the box's" {
  // (its border takes no room: what is laid out to its edge is not cut there, the border drawn over it)
  let t = Tester::new(
    fn(c) {
      c.box(w=Px(100.0), h=Px(40.0), bg=0xFFFFFFFFL, border=1.0, border_color=0xD2D2D73FL, radius=8.0, clip=true, fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), bg=0x2233AAFFL, fn() {  }) |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=100.0,
  )
  ignore(t)
  let c = g()
  // (what it holds: the instance of its colour, its clip 16-19, its corners 24-27)
  let k = (0).until(c.ninst).iter().find_first(fn(k) { c.inst[k * inst_size + 5] == 0.0 && c.inst[k * inst_size + 9] == 51.0 / 255.0 }).unwrap()
  let at = k * inst_size
  assert_eq([c.inst[at + 16], c.inst[at + 17], c.inst[at + 18], c.inst[at + 19]], [0.0, 0.0, 100.0, 40.0])
  assert_eq(c.inst[at + 24], 8.0)
}

///|
test "a node of the window's tree that clips, with an edge, cuts what it holds at its edge, its corners its own: as an old view's box with a border does" {
  // (View::edge takes no room either: what is laid out to its edge is not cut there, the edge drawn over it; the
  // window's tree's clip (view_paint's push_box_clip) and an old view's (push_round_clip) the same)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.offset(Is((100.0, 100.0))).width(Is(Some(100.0))).height(Is(Some(40.0))).radius(Is(8.0)).ground(Is(0xFFFFFFFFL)).edge(Is((1.0, 0xD2D2D73FL))).clips(Is(true))
      |> ignore
      n.box(fn(k) { k.width(Is(Some(100.0))).height(Is(Some(40.0))).ground(Is(0x2233AAFFL)) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  let c = g()
  let k = (0).until(c.ninst).iter().find_first(fn(k) { c.inst[k * inst_size + 5] == 0.0 && c.inst[k * inst_size + 9] == 51.0 / 255.0 })
  guard k is Some(k) else { fail("what the node holds not drawn") }
  let at = k * inst_size
  assert_eq([c.inst[at + 16], c.inst[at + 17], c.inst[at + 18], c.inst[at + 19]], [100.0, 100.0, 200.0, 140.0])
  assert_eq([c.inst[at + 24], c.inst[at + 25], c.inst[at + 26], c.inst[at + 27]], [8.0, 8.0, 8.0, 8.0])
}

///|
test "a box holding nothing draws its border with its ground, once" {
  let t = Tester::new(
    fn(c) {
      c.box(w=Px(100.0), h=Px(40.0), bg=0xFFFFFFFFL, border=1.0, border_color=0xD2D2D7FFL, fn() {  }) |> ignore
    },
    w=200.0,
    h=100.0,
  )
  ignore(t)
  let gs = grounds()
  assert_eq(gs.length(), 1)
  assert_eq(gs[0].5, 1.0)
  assert_eq(gs[0].4, 1.0)
}
