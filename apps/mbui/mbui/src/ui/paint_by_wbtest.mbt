// A notch and a cut worked out as they are painted (Ctx::notch_by, Ctx::cut_across_by): the outline of what is drawn
// and what shows of it, tapped whole where it is laid out, painted again as what they read changes, nothing built or
// laid out for it.

///|
/// Where the last frame drew the ground 100 by 20: its clip across, from its own left (None: not drawn).
fn ground_cut_across() -> (Double, Double)? {
  let c = g()
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 0.0 && c.inst[b + 2] == 100.0 && c.inst[b + 3] == 20.0 {
      let x = c.inst[b]
      return Some((dmax(c.inst[b + 16], x) - x, dmin(c.inst[b + 18], x + 100.0) - x))
    }
  }
  None
}

///|
/// A box 100 by 20 holding a ground as large, the box drawn only across where `cut` has it as it is painted, its
/// presses counted in `taps`.
fn cut_tester(cut : @signals.Signal[(Double, Double)], taps : Ref[Int]) -> Tester {
  Tester::new(fn(c) {
    let id = c.id("cut")
    if c.clicked(id) {
      taps.val = taps.val + 1
    }
    let b = c.box(w=Px(100.0), h=Px(20.0), id~, fn() {
      c.box(w=Px(100.0), h=Px(20.0), bg=0xFF0000FFL, fn() {  }) |> ignore
    })
    c.cut_across_by(b, fn() { cut.get() })
  })
}

///|
test "cut across as it is painted: what shows of it where the cut has it then, nothing past its edges, tapped whole" {
  let cut = @signals.signal((20.0, 60.0))
  let taps = Ref(0)
  let t = cut_tester(cut, taps)
  t.draw()
  // (built whole once more: what it laid out settled, the same twice)
  t.clock_frame()
  assert_eq(ground_cut_across(), Some((20.0, 60.0)))
  // (the cut moved: painted again so alone, nothing built or laid out; drawn whole as well and compared, looks_check)
  let was = paints_alone.val
  cut.set((30.0, 90.0))
  t.clock_frame()
  assert_eq(paints_alone.val - was, 1, msg=t.built_why())
  assert_eq(ground_cut_across(), Some((30.0, 90.0)))
  // reaching past its edges: only what is in it
  cut.set((-40.0, 50.0))
  t.clock_frame()
  assert_eq(ground_cut_across(), Some((0.0, 50.0)))
  // wholly past them, or nothing between: nothing of it drawn, and it is tapped all the same where it is laid out
  cut.set((120.0, 140.0))
  t.clock_frame()
  assert_eq(ground_cut_across(), None)
  cut.set((60.0, 40.0))
  t.clock_frame()
  assert_eq(ground_cut_across(), None)
  t.tap(90.0, 10.0)
  assert_eq(taps.val, 1)
}

///|
test "a notch as it is painted: the outline where it has it then, none at a radius of 0; drawn again alone" {
  let notch = @signals.signal((-4.0, 20.0, 8.0))
  let t = Tester::new(fn(c) {
    let b = c.box(w=Px(200.0), h=Px(40.0), bg=0x2040FFFFL, fn() {  })
    c.notch_by(b, fn() { notch.get() })
  })
  t.draw()
  t.clock_frame()
  let at_first = t.drawn_notches().map(fn(n) { (n.0, n.2, n.3, n.4) })
  assert_eq(at_first, [(0, -4.0, 20.0, 8.0)])
  let was = paints_alone.val
  notch.set((-2.0, 10.0, 8.0))
  t.clock_frame()
  assert_eq(paints_alone.val - was, 1, msg=t.built_why())
  assert_eq(t.drawn_notches().map(fn(n) { (n.0, n.2, n.3, n.4) }), [(0, -2.0, 10.0, 8.0)])
  notch.set((0.0, 0.0, 0.0))
  t.clock_frame()
  assert_eq(t.drawn_notches().length(), 0)
}
