// A press's ripple (ripple.mbt) as Android's RippleDrawable draws it under Compose's `clickable`, at declared moments.

///|
fn ripple_near(a : Double, b : Double) -> Bool {
  (a - b).abs() <= 1.0e-6
}

///|
/// A 200 × 50 box at the window's corner that ripples as it is pressed.
fn ripple_tester() -> @ui.Tester {
  @ui.Tester::new(fn(c) {
    let id = c.id("row")
    c.box(w=Px(200.0), h=Px(50.0), id~, fn() { @motion.ripple(c, id, 0.0) }) |> ignore
  })
}

///|
/// Its disc's reach at full progress: 2.3 times the box's half diagonal and 10 more.
fn ripple_most() -> Double {
  2.3 * ((200.0 * 200.0 + 50.0 * 50.0).sqrt() / 2.0 + 10.0)
}

///|
test "a press ripples from the finger to the box's middle, held at its middle; let go, it fades out" {
  let t = ripple_tester()
  t.press_at(20.0, 25.0)
  // as the finger goes down, nothing yet (its radius none)
  assert_eq(t.drawn_shadows().length(), 0)
  // its way in over: in the middle, half its reach, faded by a sixth ((.5 − .4) / .6 of .1 black)
  t.run_for(@motion.ripple_enter_ms)
  let s = t.drawn_shadows()
  assert_eq(s.length(), 1)
  let (x, y, w, h, corner, _, colour) = s[0]
  assert_true(ripple_near(x + w / 2.0, 100.0) && ripple_near(y + h / 2.0, 25.0))
  assert_true(ripple_near(w, ripple_most()) && ripple_near(corner, ripple_most() / 2.0))
  assert_eq(colour, 0x00000016L)
  // held: it stays so
  t.run_for(@motion.ripple_enter_ms)
  assert_eq(t.drawn_shadows()[0].6, 0x00000016L)
  // let go: gone by its way out's end
  t.release(20.0, 25.0)
  t.run_for(@motion.ripple_exit_ms)
  assert_eq(t.drawn_shadows().length(), 0)
  t.assert_idle()
}

///|
test "a tap however short is shown whole: its way in, then out" {
  let t = ripple_tester()
  t.tap(180.0, 10.0)
  // half way out (its way in whole first, from the tap's frame or the one after it that says it): in the middle, its
  // progress (its reach's share) near .75, faded by (p − .4) / .6 of .1 black
  t.run_for(@motion.ripple_enter_ms + @motion.ripple_exit_ms / 2.0)
  let s = t.drawn_shadows()
  assert_eq(s.length(), 1)
  let (x, y, w, _, _, _, colour) = s[0]
  assert_true(ripple_near(x + w / 2.0, 100.0) && ripple_near(y + w / 2.0, 25.0))
  let p = w / 2.0 / ripple_most()
  assert_true(p > 0.7 && p <= 0.75, msg="progress \{p}")
  assert_eq(colour & 0xFFL, (26.0 * (1.0 - (p - 0.4) / 0.6)).round().to_int64())
  t.run_for(@motion.ripple_exit_ms)
  assert_eq(t.drawn_shadows().length(), 0)
  t.assert_idle()
}
