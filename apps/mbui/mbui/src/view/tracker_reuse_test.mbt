// A pointer tracker can be reused across gestures and asked for its velocity more than once per gesture.

///|
test "a reused tracker gives the same velocity as a fresh one for the current gesture" {
  let reused = @view.Tracker::new()
  for gesture in 0..<8 {
    reused.reset()
    let samples : Array[(Double, Double)] = []
    // Include more than a ring's worth of samples, and a pause that cuts the fit short.
    let mut at = 0.0
    for i in 0..<45 {
      at += if i == 23 { 50.0 } else { 4.0 + (i % 3).to_double() }
      let x = (i * i - 13 * i + gesture * 17).to_double() / 7.0
      samples.push((at, x))
      reused.add(at, x)
      let fresh = @view.Tracker::new()
      for sample in samples {
        fresh.add(sample.0, sample.1)
      }
      assert_eq(reused.velocity(), fresh.velocity())
      // Repeating a read without a new input must not change the result either.
      assert_eq(reused.velocity(), fresh.velocity())
    }
  }
}
