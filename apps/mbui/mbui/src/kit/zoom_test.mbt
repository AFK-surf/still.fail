// A picture's zoom (zoom.mbt): fitted within its margin and never enlarged, pinched round the fingers and kept within
// the stage, a double tap in and back, and a stage's own (fitted edge to edge) resized keeping a point in sight.

///|
fn near_rect(r : (Double, Double, Double, Double)?, x : Double, y : Double, w : Double, h : Double) -> Bool {
  match r {
    Some((a, b, c, d)) => (a - x).abs() < 0.0001 && (b - y).abs() < 0.0001 && (c - w).abs() < 0.0001 && (d - h).abs() < 0.0001
    None => false
  }
}

///|
test "fitted within a margin, never enlarged; pinched round a point that stays put; kept within the stage" {
  let z = @kit.Zoom::new()
  z.boxed(390.0, 844.0)
  z.natural(600.0, 400.0)
  // (390 - 24) / 600
  assert_true((z.scale - 366.0 / 600.0).abs() < 0.0001)
  assert_true(near_rect(z.rect(), 12.0, 300.0, 366.0, 244.0))
  let small = @kit.Zoom::new()
  small.boxed(390.0, 844.0)
  small.natural(100.0, 50.0)
  assert_eq(small.scale, 1.0)
  // twice as large round (100, 422): that point of the picture stays under it
  let (x0, _, w0, _) = z.rect().unwrap()
  let u = (100.0 - x0) / w0
  z.transform(100.0, 422.0, 2.0, 0.0, 0.0)
  let (x1, _, w1, _) = z.rect().unwrap()
  assert_true((x1 + u * w1 - 100.0).abs() < 0.0001)
  assert_true(z.zoomed())
  // panned far: no gap at its edges
  z.pan(10000.0, 0.0)
  assert_true(z.rect().unwrap().0.abs() < 0.0001)
  // no further than 16 times
  z.transform(195.0, 422.0, 1000.0, 0.0, 0.0)
  assert_true((z.scale - 16.0).abs() < 0.0001)
}

///|
test "a stage's own: fitted edge to edge, the keyboard up keeping the frame as large and its point in sight" {
  let z = @kit.Zoom::new(margin=fn(_) { 0.0 }, enlarge=true, min_scale=fn(fit) { fit }, max_scale=fn(fit) {
    fit * 5.0
  })
  z.natural(1280.0, 720.0)
  z.boxed(800.0, 360.0)
  assert_true(near_rect(z.rect(), 80.0, 0.0, 640.0, 360.0))
  z.resize_keeping(800.0, 150.0, Some((0.5, 0.9)), 40.0)
  let (_, y, w, h) = z.rect().unwrap()
  assert_true((w - 640.0).abs() < 0.0001)
  assert_true(y + 0.9 * h >= 0.0 && y + 0.9 * h <= 150.0)
  z.resize_keeping(800.0, 360.0, Some((0.5, 0.9)), 40.0)
  assert_true(!z.zoomed())
  z.fit_now()
  assert_true(near_rect(z.rect(), 80.0, 0.0, 640.0, 360.0))
}
