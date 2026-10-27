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
