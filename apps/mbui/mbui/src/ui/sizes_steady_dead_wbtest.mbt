// What sizes_steady calls stopped dead: a step in how fast a measure slows as it comes to rest, not where its rest falls
// among the frames (sizes_steady_fault, stop_jerk).

///|
/// A measure's samples (each frame's moment, drawn then, and the measure) `period` apart, its speed a frame at each.
fn dead_samples(speeds : Array[Double], period : Double) -> Array[(Double, Double, Double)] {
  let out = [(1000.0, 1000.0, 100.0)]
  let mut x = 100.0
  for i, v in speeds {
    x = x + v
    let t = 1000.0 + (i + 1).to_double() * period
    out.push((t, t, x))
  }
  out
}

///|
fn dead_said(speeds : Array[Double], period : Double) -> Bool {
  let (said, _) = sizes_steady_fault(dead_samples(speeds, period), period, turned=-1.0)
  said is Some(s) && s.contains("stopped dead")
}

///|
test "stopped dead: at speed, then still in a frame, said; as fast or a little slower before, said" {
  let period = 1000.0 / 60.0
  assert_true(dead_said([10.0, 10.0, 10.0, 0.0], period))
  assert_true(dead_said([10.0, 10.0, 9.0, 0.0], period))
  assert_true(dead_said([10.0, 10.0, 0.0], period))
  assert_true(dead_said([10.0, 9.0, 0.0], period))
  // (going faster, then still)
  assert_true(dead_said([16.5, 18.4, 0.0], period))
  // (as come_group's turned back, before: 12.9, 12.95, then slowing 5.3 and 6.3 a frame)
  assert_true(dead_said([12.9, 12.95, 7.68, 1.38], period))
}

///|
test "stopped dead: slowing at one rate to rest, wherever its rest falls among the frames and at any rate, not said" {
  for rate in [7.0, 24.0, 60.0, 120.0] {
    let period = 1000.0 / rate
    for phase in [0.0, 0.25, 0.5, 0.75] {
      // (from 20 a 60th of a second, slowing 4 a 60th each 60th, sampled every frame of `rate`, at rest once there)
      let a = 4.0 / (1000.0 / 60.0) / (1000.0 / 60.0)
      let v0 = 20.0 / (1000.0 / 60.0)
      let stop = v0 / a
      let at = fn(t : Double) {
        let u = if t < stop { t } else { stop }
        v0 * u - a * u * u / 2.0
      }
      let samples = []
      let mut k = 0
      while k < 12 {
        let t = (k.to_double() + phase) * period
        samples.push((1000.0 + t, 1000.0 + t, at(t)))
        let (said, _) = sizes_steady_fault(samples, period, turned=-1.0)
        assert_true(!(said is Some(s) && s.contains("stopped dead")), msg="\{rate} \{phase} at \{k}: \{Repr(said)}")
        k = k + 1
      }
    }
  }
}

///|
test "stopped dead: what it does after has no part in it" {
  let period = 1000.0 / 60.0
  // (slowing at one rate to rest, or on through it a little: not said, whether it turns back after or not; it is judged
  // on the frame it comes to rest, as drawn, what comes after unseen then)
  assert_true(!dead_said([12.0, 8.0, 4.0, 0.0], period))
  assert_true(!dead_said([12.0, 8.0, 4.0, -0.1], period))
  assert_true(!dead_said([12.0, 8.0, 4.0, 0.3], period))
  // (at speed, then still: said, as it will turn back after or not)
  assert_true(dead_said([10.0, 10.0, 0.0], period))
  assert_true(dead_said([10.0, 10.0, -0.5], period))
}
