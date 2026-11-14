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
/// Whether this frame draws a rect of the grey `v` (each channel, of 255).
fn ground_drawn(v : Int) -> Bool {
  let c = g()
  let x = v.to_double() / 255.0
  for k in 0..<c.ninst {
    let q = k * inst_size
    if c.inst[q + 5] == 0.0 && (c.inst[q + 8] - x).abs() < 0.002 && (c.inst[q + 9] - x).abs() < 0.002 {
      return true
    }
  }
  false
}

///|
/// A window drawn in the theme `dark` says, with a box of its ground.
fn themed_page(dark : @signals.Signal[Bool]) -> (Ctx) -> Unit {
  fn(c) {
    c.with_theme(if dark.get() { Theme::dark() } else { Theme::light() }, fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), bg=if dark.get() { 0x111111FFL } else { 0xEEEEEEFFL }, fn() {  }) |> ignore
    })
  }
}

///|
test "a change of theme spreads from where it was asked, from the frame first drawn in it" {
  let dark = @signals.signal(false)
  let t = Tester::new(themed_page(dark), w=400.0, h=300.0)
  t.frame()
  reveal_from(100.0, 50.0, dark=fn() { dark.get() })
  // (the theme the app's settings take a frame later)
  t.frame()
  assert_eq(reveal.start, -1.0)
  assert_eq(circle_radius(), -1.0)
  dark.set(true)
  t.frame()
  assert_true(reveal.start >= 0.0)
  let first = circle_radius()
  assert_true(first > 0.0)
  t.run_for(reveal_ms / 2.0)
  let half = circle_radius()
  assert_true(half > first)
  // the window as it was under it (its light ground), the window as it is in it (its dark one)
  assert_true(ground_drawn(0xEE) && ground_drawn(0x11))
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
  assert_false(reveal.on)
}

///|
test "while it spreads, what is outside the circle yet is pressed as it is laid out" {
  let dark = @signals.signal(false)
  let presses = Ref(0)
  let t = Tester::new(fn(c) {
    c.with_theme(if dark.get() { Theme::dark() } else { Theme::light() }, fn() {
      let b = c.id("far")
      c.box(w=Fill(1.0), h=Fill(1.0), bg=0xEEEEEEFFL, fn() {
        c.box(id=b, w=Px(60.0), h=Px(40.0), tx=300.0, ty=240.0, bg=0x336699FFL, fn() {  }) |> ignore
      })
      |> ignore
      c.on_press(b, fn() {
        presses.val += 1
      })
    })
  }, w=400.0, h=300.0)
  t.frame()
  reveal_from(10.0, 10.0, dark=fn() { dark.get() })
  t.frame()
  dark.set(true)
  t.frame()
  assert_true(circle_radius() > 0.0 && circle_radius() < 100.0)
  t.tap(330.0, 260.0)
  assert_eq(presses.val, 1)
}

///|
test "a reveal asked with no change of theme is let go" {
  let dark = @signals.signal(false)
  let t = Tester::new(themed_page(dark), w=400.0, h=300.0)
  t.frame()
  reveal_from(100.0, 50.0, dark=fn() { dark.get() })
  assert_true(reveal.on)
  t.run_for(reveal_wait_most + 100.0)
  t.frame()
  assert_false(reveal.on)
  assert_eq(circle_radius(), -1.0)
}

///|
test "at a large window's size too, the old window is drawn again under the circle from the frame it sets out" {
  let dark = @signals.signal(false)
  let t = Tester::new(themed_page(dark), w=1512.0, h=982.0)
  t.frame()
  reveal_from(700.0, 300.0, dark=fn() { dark.get() })
  dark.set(true)
  t.frame()
  assert_true(reveal.start >= 0.0)
  assert_true(ground_drawn(0xEE) && ground_drawn(0x11))
}

///|
test "where the window is the tree's: its ground and an old view's words in it over the window as it was, in the circle; no words over words" {
  let dark = @signals.signal(false)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, words_over_held=false, tree=fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(400.0)))
      .height(Is(Some(300.0)))
      .ground(By(fn() { if dark.get() { 0x111111FFL } else { 0xEEEEEEFFL } }))
      |> ignore
      // (the words an old view's, on the tree's ground: the same words in the same place in either theme)
      old(b, fn(c) {
        c.with_theme(if dark.get() { Theme::dark() } else { Theme::light() }, fn() { c.text("未开启") |> ignore })
      })
      .width(Is(Some(200.0)))
      .height(Is(Some(100.0)))
      |> ignore
    })
    |> ignore
  })
  t.frame()
  reveal_from(20.0, 10.0, dark=fn() { dark.get() })
  t.frame()
  dark.set(true)
  t.frame()
  assert_true(reveal.start >= 0.0)
  t.run_for(reveal_ms / 2.0)
  // the window as it was under it, the tree's ground as it is in it
  assert_true(circle_radius() > 0.0)
  assert_true(ground_drawn(0xEE) && ground_drawn(0x11))
  // (the words as they were under the tree's ground, not seen through to the words as they are)
  let over = t.words_over_frames()
  assert_true(over.is_empty(), msg="words over words: \{Repr(over)}")
  t.run_for(reveal_ms / 2.0)
  assert_false(reveal.on)
}
