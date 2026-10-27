// A change of theme spreading from where it was asked (reveal.mbt): set out in the frame the view is first drawn in
// another theme, a circle growing over the picture of the window as it was, gone once it covers it; let go when the
// theme does not change.

///|
/// The circle the view is drawn in this frame: its radius (-1 none), as the instances painted are cut to it.
fn circle_radius() -> Double {
  let c = g()
  for k in 0..<c.ninst {
    let q = k * inst_size
    let r = c.inst[q + 24]
    if r > 0.0 && c.inst[q + 25] == r && c.inst[q + 18] - c.inst[q + 16] == 2.0 * r {
      return r
    }
  }
  -1.0
}

///|
/// A window drawn in the theme `dark` says, with a box of its ground.
fn themed_page(dark : Ref[Bool]) -> (Ctx) -> Unit {
  fn(c) {
    c.with_theme(if dark.val { Theme::dark() } else { Theme::light() }, fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), bg=if dark.val { 0x111111FFL } else { 0xEEEEEEFFL }, fn() {  }) |> ignore
    })
  }
}

///|
test "a change of theme spreads from where it was asked, from the frame first drawn in it" {
  let dark = Ref(false)
  let t = Tester::new(themed_page(dark), w=400.0, h=300.0)
  t.frame()
  g().reveal_from(100.0, 50.0, dark=fn() { dark.val })
  // (the theme the app's settings take a frame later)
  t.frame()
  assert_eq(reveal.start, -1.0)
  assert_eq(circle_radius(), -1.0)
  dark.val = true
  t.frame()
  assert_true(reveal.start >= 0.0)
  let first = circle_radius()
  assert_true(first > 0.0)
  t.run_for(reveal_ms / 2.0)
  let half = circle_radius()
  assert_true(half > first)
  // (as far as the corner furthest from where it spreads: 300 across, 250 down)
  assert_true(half < (300.0 * 300.0 + 250.0 * 250.0).sqrt())
  // (cut to the circle where it is past the window's edges too, not to the square it leaves within them)
  let c = g()
  let mut past = false
  for k in 0..<c.ninst {
    let q = k * inst_size
    if c.inst[q + 24] == half && c.inst[q + 16] < 0.0 && c.inst[q + 17] < 0.0 {
      past = true
    }
  }
  assert_true(past)
  t.run_for(reveal_ms / 2.0)
  assert_eq(circle_radius(), -1.0)
  assert_eq(reveal.key, "")
}

///|
test "while it spreads, what is outside the circle yet is pressed as it is laid out" {
  let dark = Ref(false)
  let presses = Ref(0)
  let t = Tester::new(fn(c) {
    c.with_theme(if dark.val { Theme::dark() } else { Theme::light() }, fn() {
      let b = c.id("far")
      c.box(w=Fill(1.0), h=Fill(1.0), bg=0xEEEEEEFFL, fn() {
        c.box(id=b, w=Px(60.0), h=Px(40.0), tx=300.0, ty=240.0, bg=0x336699FFL, fn() {  }) |> ignore
      })
      |> ignore
      if c.clicked(b) {
        presses.val += 1
      }
    })
  }, w=400.0, h=300.0)
  t.frame()
  g().reveal_from(10.0, 10.0, dark=fn() { dark.val })
  t.frame()
  dark.val = true
  t.frame()
  assert_true(circle_radius() > 0.0 && circle_radius() < 100.0)
  t.tap(330.0, 260.0)
  assert_eq(presses.val, 1)
}

///|
test "a reveal asked with no change of theme is let go" {
  let dark = Ref(false)
  let t = Tester::new(themed_page(dark), w=400.0, h=300.0)
  t.frame()
  g().reveal_from(100.0, 50.0, dark=fn() { dark.val })
  assert_true(reveal.key != "")
  t.run_for(reveal_wait_most + 100.0)
  t.frame()
  assert_eq(reveal.key, "")
  assert_eq(circle_radius(), -1.0)
}
