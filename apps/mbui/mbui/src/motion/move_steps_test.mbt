///|
/// How far the test's way goes (points).
let move_steps_far : Double = 300.0

///|
/// A Move's place at each of the display's frames `period` apart, from its start to its end, as the way reads it.
fn move_steps_places(period : Double) -> (Array[Double], Array[Double]) {
  let spec = @motion.moved()
  let dur = spec.duration(0.0, move_steps_far, 0.0)
  let placed = []
  let exact = []
  let mut k = 0
  while k.to_double() * period <= dur {
    let t = k.to_double() * period
    placed.push(spec.value_at(t, dur, 0.0, move_steps_far, 0.0).0)
    // (its way at the frame's moment, on the moments' grid: @ui.gone_ms, 1e-6 ms. The grid itself makes no step: at a
    // way's fastest, some 3 points a ms, 1e-6 ms is 3e-6 points, far under a device's pixel; a coarser grid is a step
    // of its own, as whole ms was (8, 8, 9 ms at 120 a second))
    exact.push(@ui.move_path(-move_steps_far, 0.0, @ui.gone_ms(t), dur).0 + move_steps_far)
    k += 1
  }
  (placed, exact)
}

///|
test "a Move drawn at the display's frames, 60 and 120 a second: at each frame where its way is at that very moment, and past its fastest step every step shorter than the one before" {
  for rate in [60.0, 120.0] {
    let (placed, exact) = move_steps_places(1000.0 / rate)
    for i, x in placed {
      assert_true(x == exact[i], msg="at \{rate} a second, frame \{i}: placed \{x}, its way \{exact[i]}")
    }
    let steps = []
    for i in 1..<placed.length() {
      steps.push(placed[i] - placed[i - 1])
    }
    let mut fastest = 0
    for i, s in steps {
      if s > steps[fastest] {
        fastest = i
      }
    }
    for i in (fastest + 1)..<steps.length() {
      assert_true(steps[i] <= steps[i - 1], msg="at \{rate} a second, step \{i}: \{steps[i]} after \{steps[i - 1]} (\{Repr(steps)})")
    }
  }
}
