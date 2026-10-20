// scroll.mbt against Compose's formulas (the expected values come from
// scripts/scrollplot.py table, a reference written apart from this), and
// lists scrolled by scripted touches as each platform's would scroll.

///|
fn approx(got : Double, want : Double, tol : Double) -> Unit raise {
  if (got - want).abs() > tol || got != got {
    fail("got \{got}, want \{want} ± \{tol}")
  }
}

///|
fn track_of(samples : Array[(Double, Double)]) -> Tracker {
  let tr = Tracker::new()
  for s in samples {
    tr.add(s.0, s.1)
  }
  tr
}

///|
test "the velocity tracker fits a quadratic to the last samples (Compose's Lsq2)" {
  // exactly a quadratic: its slope at the newest sample
  let q = track_of(
    Array::makei(13, fn(i) {
      let t = i.to_double() * 8.0
      (t, 0.002 * t * t + 1.5 * t)
    }),
  )
  approx(q.velocity(), 1.884, 1.0e-9)
  // uneven samples, as Compose computes them
  let u = track_of([
    (0.0, 0.0),
    (3.0, 5.0),
    (16.0, 20.0),
    (21.0, 31.0),
    (33.0, 52.0),
  ])
  approx(u.velocity(), 2.0533202144613862, 1.0e-9)
  // two samples: a straight line
  approx(track_of([(0.0, 0.0), (10.0, 5.0)]).velocity(), 0.5, 1.0e-12)
  // one: nothing to tell
  approx(track_of([(5.0, 1.0)]).velocity(), 0.0, 0.0)
}

///|
test "the velocity tracker forgets samples over 100 ms old and stops at a 40 ms pause" {
  // 1 px/ms until 100 ms, then 3: only the last 100 ms count
  let samples = []
  for i in 0..=20 {
    let t = i.to_double() * 10.0
    samples.push((t, if t <= 100.0 { t } else { 100.0 + (t - 100.0) * 3.0 }))
  }
  approx(track_of(samples).velocity(), 3.0, 1.0e-9)
  // moving, then held still 50 ms before the newest sample: not moving
  let held = Array::makei(9, fn(i) {
    let t = i.to_double() * 8.0
    (t, 3.0 * t)
  })
  held.push((114.0, 192.0))
  approx(track_of(held).velocity(), 0.0, 0.0)
  // the ring keeps 20: older ones are gone
  let many = track_of(
    Array::makei(40, fn(i) {
      let t = i.to_double() * 4.0
      (t, if i < 20 { 0.0 } else { (t - 76.0) * 2.0 })
    }),
  )
  approx(many.velocity(), 2.0, 1.0e-9)
}

///|
test "the fling spline is Android's (computeSplineInfo)" {
  // the bisection stops within 1e-5 of the time, not at 0
  approx(spline_positions[0], 0.0, 1.0e-4)
  approx(spline_positions[10], 0.2740024733220569, 1.0e-9)
  approx(spline_positions[35], 0.7217749311525871, 1.0e-9)
  approx(spline_positions[70], 0.9567898524767604, 1.0e-9)
  approx(spline_positions[100], 1.0, 0.0)
}

///|
test "a fling goes as far and as long as Compose's (FlingCalculator)" {
  // distance in dp and duration in ms by velocity in dp/ms; the same at any
  // density
  let want = [
    (0.5, 58.3223, 333.0, 38.4301, 58.0823),
    (1.0, 194.3136, 555.0, 88.7585, 171.9111),
    (2.0, 647.3988, 924.0, 190.6827, 447.3551),
    (4.0, 2156.9521, 1540.0, 392.8148, 1047.6453),
    (8.0, 7186.3628, 2566.0, 794.8395, 2269.5407),
  ]
  for density in [2.625, 3.0] {
    for w in want {
      let (v, dist, dur, at100, at300) = w
      let (d, ms) = spline_fling(v * 1000.0 * density, density)
      approx(d / density, dist, 0.001)
      approx(ms, dur, 0.0)
      approx(spline_at(100.0, ms).0 * d / density, at100, 0.001)
      approx(spline_at(300.0, ms).0 * d / density, at300, 0.001)
    }
  }
  // the end: all of it, still
  let (share, vc) = spline_at(5000.0, 924.0)
  approx(share, 1.0, 0.0)
  approx(vc, 0.0, 0.0)
}

///|
test "Android's stretch: EdgeEffect's intensity and HWUI's mapping" {
  approx(stretch_amount(0.0), 0.0, 1.0e-12)
  // 0.016 x + 0.016 (1 - e^(-x e / 0.33))
  approx(
    stretch_amount(0.25),
    0.004 + 0.016 * (1.0 - @math.exp(-0.25 * 2.718281828459045 / 0.33)),
    1.0e-12,
  )
  // the pulled edge stays, the far one goes out of view; the content near the
  // pulled edge stretches most
  let ov = stretch_amount(0.5)
  approx(stretch_map(ov, 0.0), 0.0, 1.0e-12)
  assert_true(stretch_map(ov, 1.0) > 1.0)
  assert_true(stretch_map(ov, 0.1) / 0.1 > (stretch_map(ov, 1.0) - stretch_map(ov, 0.9)) / 0.1)
  approx(stretch_map(-ov, 1.0), 1.0, 1.0e-12)
  assert_true(stretch_map(-ov, 0.0) < 0.0)
  // it inverts the shader's map (computeOverscrollStart)
  for p in [0.1, 0.4, 0.8] {
    let out = stretch_map(ov, p)
    let back = 1.0 / (1.0 + ov) - (1.0 - out) / (1.0 + ov * (0.3 + 0.7 * (1.0 - out)))
    approx(back, p, 1.0e-6)
  }
}

///|
let clicks : Array[Int] = []

///|
/// `n` rows 50 high, each one that takes taps.
fn rows_view(n : Int) -> (Ctx) -> Unit {
  fn(c) {
    c.list("l", n, 50.0, fn(i) {
      let id = c.id("row")
      c.box(h=Px(50.0), bg=0xEEEEEEFFL, id~, fn() { c.text("row \{i}") |> ignore })
      |> ignore
      if c.clicked(id) {
        clicks.push(i)
      }
    })
    |> ignore
  }
}

///|
/// A finger down at (200, y0), moved `dy` every half a drag step (8 ms) `steps` times, let go
/// with the last move.
fn swipe(t : Tester, y0 : Double, dy : Double, steps : Int) -> Unit {
  t.touch(0, 200.0, y0)
  for k in 1..=steps {
    t.advance(drag_step_ms / 2.0)
    t.touch(1, 200.0, y0 + dy * k.to_double())
  }
  t.touch(2, 200.0, y0 + dy * steps.to_double())
}

///|
/// The list's own motion run to its end (its fling, its overscroll going back, its scroll bar faded: what it said as
/// it set out, scroll_path.mbt), and nothing after.
fn run_to_rest(t : Tester) -> Unit {
  let r = t.rest_of("a list")
  if r > t.time() {
    t.run_for(r - t.time())
  }
  t.assert_idle()
}

///|
test "Android: a fling follows Compose's spline frame by frame, from the velocity of the touches" {
  let t = Tester::new(rows_view(500), platform=2)
  // 3 dp/ms up for 96 ms; the drag starts where the 8 dp slop ends
  swipe(t, 700.0, -24.0, 12)
  t.frame()
  let start = 12.0 * 24.0 - 8.0
  let (dist, dur) = spline_fling(3.0 * 1000.0 * 2.0, 2.0)
  let dist = dist / 2.0
  // playtime 0 at the first frame after the finger left, as Compose's (where
  // the spline is not quite 0)
  approx(t.list_offset(), start + spline_at(0.0, dur).0 * dist, 1.0e-9)
  let t0 = t.time()
  let mut frames = 0
  while t.list_moving() && frames < 400 {
    t.frame()
    frames = frames + 1
    let played = t.time() - t0
    let want = spline_at(played, dur).0 * dist
    approx(t.list_offset() - start, want, 0.01)
  }
  approx(t.list_offset() - start, dist, 0.01)
  // it ends at the frame its duration is over
  approx((frames * 16).to_double(), dur, 16.0)
}

///|
test "Android: the drag starts where the slop ends, nothing jumps or is lost" {
  let t = Tester::new(rows_view(100), platform=2)
  t.touch(0, 200.0, 500.0)
  t.advance(drag_step_ms / 2.0)
  t.touch(1, 200.0, 495.0)
  t.frame(ms=0.0)
  approx(t.list_offset(), 0.0, 0.0)
  t.advance(drag_step_ms / 2.0)
  t.touch(1, 200.0, 490.0)
  t.frame(ms=0.0)
  approx(t.list_offset(), 2.0, 1.0e-9)
  t.advance(drag_step_ms / 2.0)
  t.touch(1, 200.0, 480.0)
  t.frame(ms=0.0)
  approx(t.list_offset(), 12.0, 1.0e-9)
  // held still before letting go, longer than the velocity tracker looks back: no fling
  t.advance(tracker_horizon_ms)
  t.touch(1, 200.0, 480.0)
  t.touch(2, 200.0, 480.0)
  t.frame()
  assert_false(t.list_moving())
  approx(t.list_offset(), 12.0, 1.0e-9)
  // elsewhere the slop is 6
  let m = Tester::new(rows_view(100))
  m.touch(0, 200.0, 500.0)
  m.advance(drag_step_ms / 2.0)
  m.touch(1, 200.0, 490.0)
  m.frame(ms=0.0)
  approx(m.list_offset(), 4.0, 1.0e-9)
}

///|
test "Android: pulled past the top it stretches, the rows drawn stretched, and goes back when let go" {
  let t = Tester::new(rows_view(100), platform=2)
  let row1 = t.row(1).unwrap().1
  t.touch(0, 200.0, 300.0)
  for k in 1..=10 {
    t.advance(drag_step_ms)
    t.touch(1, 200.0, 300.0 + 10.0 * k.to_double())
    t.draw()
  }
  // nothing scrolled; the pull past the slop, in the list's heights
  approx(t.list_offset(), 0.0, 0.0)
  approx(t.list_overscroll(), 92.0 / 844.0, 1.0e-9)
  // laid out in place, drawn lower (the stretch grows from the top)
  approx(t.row(1).unwrap().1, row1, 0.0)
  let drawn = t.drawn_rects().filter(fn(r) { r.4 == 0xEEEEEEFFL })
  assert_true(drawn[1].1 > row1 + 0.5)
  // held still, then let go: it springs back, the list where it was
  t.advance(tracker_horizon_ms)
  t.touch(2, 200.0, 400.0)
  t.frame()
  assert_true(t.list_moving())
  run_to_rest(t)
  approx(t.list_overscroll(), 0.0, 0.0)
  approx(t.list_offset(), 0.0, 0.0)
  assert_false(t.list_moving())
}

///|
test "Android: scrolling back first undoes the stretch" {
  let t = Tester::new(rows_view(100), platform=2)
  t.touch(0, 200.0, 300.0)
  t.advance(drag_step_ms)
  t.touch(1, 200.0, 408.0)
  t.frame(ms=0.0)
  approx(t.list_overscroll(), 100.0 / 844.0, 1.0e-9)
  t.advance(drag_step_ms)
  t.touch(1, 200.0, 358.0)
  t.frame(ms=0.0)
  approx(t.list_overscroll(), 50.0 / 844.0, 1.0e-9)
  approx(t.list_offset(), 0.0, 0.0)
  t.advance(drag_step_ms)
  t.touch(1, 200.0, 288.0)
  t.frame(ms=0.0)
  approx(t.list_overscroll(), 0.0, 0.0)
  approx(t.list_offset(), 20.0, 1.0e-9)
}

///|
test "Android: a fling into the end stretches there and comes back" {
  let t = Tester::new(rows_view(40), platform=2)
  swipe(t, 700.0, -24.0, 12)
  let mut stretched = 0.0
  let mut frames = 0
  while frames < 600 {
    t.frame()
    frames = frames + 1
    if t.list_overscroll() < stretched {
      stretched = t.list_overscroll()
    }
    if !t.list_moving() {
      break
    }
  }
  // 40 rows of 50 in a view 844 high
  approx(t.list_offset(), 40.0 * 50.0 - 844.0, 1.0e-6)
  assert_true(stretched < -0.05)
  approx(t.list_overscroll(), 0.0, 0.0)
}

///|
test "Android: a finger on a flinging list stops it and taps nothing" {
  clicks.clear()
  let t = Tester::new(rows_view(500), platform=2)
  swipe(t, 700.0, -24.0, 12)
  t.run_for(5.0 * drag_step_ms)
  assert_true(t.list_moving())
  let at = t.list_offset()
  t.touch(0, 200.0, 400.0)
  t.frame()
  t.touch(2, 200.0, 400.0)
  t.frame()
  t.draw()
  assert_false(t.list_moving())
  approx(t.list_offset(), at, 0.0)
  assert_eq(clicks.length(), 0)
  // at rest, a tap taps
  t.tap(200.0, 400.0)
  assert_eq(clicks.length(), 1)
}

///|
test "iOS: decelerates as UIScrollView" {
  let t = Tester::new(rows_view(500), platform=1)
  swipe(t, 700.0, -24.0, 12)
  t.frame()
  let start = t.list_offset()
  approx(start, 12.0 * 24.0 - 6.0, 1.0e-9)
  run_to_rest(t)
  // v (0.998^t - 1) / ln 0.998 until under 0.02 px/ms: there, at its end, at whatever rate it was drawn
  let k = 0.998
  let t_end = @math.ln(0.02 / 3.0) / @math.ln(k)
  let want = 3.0 * (@math.pow(k, t_end) - 1.0) / @math.ln(k)
  approx(t.list_offset() - start, want, 3.0 * 1.0e-6)
}

///|
test "iOS: pulled past the top on a rubber band, and back" {
  // the rubber band: at the top, pulled 94 points it shows 48.7
  let r = Tester::new(rows_view(100), platform=1)
  r.touch(0, 200.0, 300.0)
  for k in 1..=10 {
    r.advance(drag_step_ms)
    r.touch(1, 200.0, 300.0 + 10.0 * k.to_double())
    r.draw()
  }
  approx(r.list_offset(), 0.0, 0.0)
  approx(r.row(0).unwrap().1, rubber(94.0, 844.0), 1.0e-9)
  approx(rubber(94.0, 844.0), 48.7, 0.1)
  r.touch(2, 200.0, 400.0)
  r.frame()
  run_to_rest(r)
  approx(r.row(0).unwrap().1, 0.0, 0.0)
  approx(r.list_overscroll(), 0.0, 0.0)
}

///|
test "the desktop: a mouse drag past the top coasts into it and stops there, nothing stretches" {
  let t = Tester::new(rows_view(40))
  swipe(t, 300.0, 20.0, 10)
  t.frame()
  run_to_rest(t)
  approx(t.list_offset(), 0.0, 0.0)
  approx(t.list_overscroll(), 0.0, 0.0)
}

///|
test "the desktop: a mouse drag coasts (v (0.997^t - 1) / ln 0.997) and stops at the end, nothing stretches" {
  let t = Tester::new(rows_view(40))
  swipe(t, 700.0, -24.0, 12)
  t.frame()
  run_to_rest(t)
  approx(t.list_offset(), 40.0 * 50.0 - 844.0, 1.0e-6)
  approx(t.list_overscroll(), 0.0, 0.0)
}
