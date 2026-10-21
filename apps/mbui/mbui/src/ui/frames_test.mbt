// Runs compared frame by frame (frames.mbt).

///|
/// How long after the last tap `counting`'s words come (ms).
let counting_later_ms = 100.0

///|
/// A view that changes with time and with a tap: a count of taps, and words that come `counting_later_ms` after the
/// last.
fn counting() -> (@ui.Ctx) -> Unit {
  let taps : Ref[Int] = Ref::new(0)
  let at : Ref[Double] = Ref::new(-1.0)
  fn(c) {
    if c.button("加一") {
      taps.val = taps.val + 1
      at.val = c.now()
      c.wake_in(counting_later_ms)
    }
    c.text("按了 \{taps.val} 次") |> ignore
    if at.val >= 0.0 && c.now() - at.val >= counting_later_ms {
      c.text("过了一会儿") |> ignore
    }
  }
}

///|
fn run(tap_at : Int) -> Array[Int64] {
  let t = @ui.Tester::new(counting(), w=320.0, h=200.0)
  let before = t.frames(tap_at)
  t.tap_text("加一")
  before + [t.frame_hash()] + t.frames(20)
}

///|
test "the same steps draw the same frames, frame for frame" {
  let a = run(5)
  let b = run(5)
  assert_eq(a.length(), 26)
  assert_eq(@ui.first_difference(a, b), None)
}

///|
test "a run that taps later parts from the other at the frame it tapped" {
  let a = run(5)
  let b = run(8)
  assert_eq(@ui.first_difference(a, b), Some(5))
}

///|
test "what a frame drew changes its hash; what it did not, does not" {
  let t = @ui.Tester::new(counting(), w=320.0, h=200.0)
  let idle = t.frames(3)
  assert_eq(idle[0], idle[2])
  t.tap_text("加一")
  let tapped = t.frame_hash()
  assert_true(tapped != idle[2])
  // the words that come 100 ms later: a frame unlike those before
  let later = t.frames(10)
  assert_true(t.find("过了一会儿") is Some(_))
  assert_true(later[9] != tapped)
}
