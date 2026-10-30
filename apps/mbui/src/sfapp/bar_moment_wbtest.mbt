// The bar told what it shows at the moment of what changed it (a page put on the stack, a place come in), whatever
// frames are drawn after: where it is at a moment a function of that moment and what was done, at 60 Hz, 120 Hz or in
// one jump; built again with nothing changed, its ways the same.

///|
/// Where the bar is at `t0 + 160` (the frames' clock) with a page put on the stack at `t0 + 10`, frames drawn at
/// `t0 +` each of `frames` between: when it set out going (from t0), how far shown and to where, the notch, the ball across, how far shown and its size.
fn bar_after_push(frames : Array[Double]) -> (Double, Double, Double, Double, Double, Double, Double) {
  let t = tester("home")
  let rest = bar_rest()
  if rest > t.time() {
    t.run_for(rest - t.time())
  }
  let t0 = t.time()
  t.advance(10.0)
  app.nav.push(Settings)
  for f in frames {
    t.frame_at(t0 + f)
  }
  t.frame_at(t0 + 160.0)
  (bar.vis.start - t0, bar.vis.value, bar.vis.target, bar.k.x, bar.ball_x.x, bar.ball_alpha.value, bar.ball_scale.value)
}

///|
test "bar: a page put on the stack between frames, the bar going from that moment: the same at a moment, whichever frames came between" {
  let one = bar_after_push([])
  let late = bar_after_push([40.0])
  let many = bar_after_push([11.0, 13.0, 16.0, 24.0, 33.0, 80.0])
  assert_eq((late, many), (one, one))
  // (going from the moment the page was put on: hidden by then, not there yet)
  assert_true((one.0 - 10.0).abs() < 0.000001 && one.1 > 0.0 && one.1 < 1.0 && one.2 == 0.0, msg="\{one}")
}

///|
test "bar: told the same again, at another moment, by a build or as the state is read again: its ways as they were" {
  let t = tester("home")
  let t0 = t.time()
  t.advance(10.0)
  app.nav.push(Settings)
  t.frame_at(t0 + 16.0)
  let ways = fn() {
    (bar.vis.start, bar.vis.from, bar.vis.target, bar.vis.dur, bar.k.to, bar.ball_x.to, bar.ball_alpha.start)
  }
  let first = ways()
  // (the same told again later, as a reaction or a build would)
  bar_tell(bar.told.unwrap(), t0 + 30.0)
  let again = ways()
  // (frames built on at other moments)
  t.frame_at(t0 + 40.0)
  t.frame_at(t0 + 41.0)
  assert_eq((again, ways()), (first, first))
  assert_eq(first.0, t0 + 10.0)
}
