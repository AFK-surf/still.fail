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

///|
test "a page on a canvas: free, dragged anywhere; its fitted scale by thousandths; its own bounds of scale" {
  let z = @kit.Zoom::new(margin=fn(_) { 16.0 }, min_scale=fn(_) { 0.05 }, max_scale=fn(_) { 4.0 }, free=true, fit_step=0.001)
  z.boxed(390.0, 600.0)
  z.natural(1280.0, 800.0)
  // (390 - 32) / 1280 = 0.2796875, down to 0.279
  assert_true((z.scale - 0.279).abs() < 0.0000001)
  // dragged far off: it goes there
  z.pan(-1000.0, 0.0)
  assert_true(z.rect().unwrap().0 < -800.0)
  // pinched down past its least: 0.05
  z.transform(195.0, 300.0, 0.01, 0.0, 0.0)
  assert_true((z.scale - 0.05).abs() < 0.0000001)
  z.fit_now()
  assert_true(z.fitted && (z.scale - 0.279).abs() < 0.0000001)
}

///|
test "what reads where a zoom shows is told as that changes, by any way it changes: resized keeping a point in place" {
  let z = @kit.Zoom::new()
  z.natural(100.0, 100.0)
  z.boxed(200.0, 200.0)
  let shown = @signals.computed(fn(_) { z.rect() })
  assert_true(near_rect(shown.get(), 50.0, 50.0, 100.0, 100.0))
  // (the stage larger, the picture's middle where it was, then kept centred: nothing to bring in sight)
  z.resize_keeping(300.0, 300.0, Some((0.5, 0.5)), 0.0)
  assert_true(near_rect(z.rect(), 100.0, 100.0, 100.0, 100.0), msg="\{z.rect()}")
  assert_eq(shown.get(), z.rect())
}

///|
test "what reads where a zoom shows is not told where nothing it shows changed, nor of another zoom" {
  let a = @kit.Zoom::new(free=true)
  a.natural(100.0, 100.0)
  a.boxed(400.0, 400.0)
  let b = @kit.Zoom::new()
  b.natural(100.0, 100.0)
  b.boxed(400.0, 400.0)
  let reads = Ref(0)
  let shown = @signals.computed(fn(_) {
    reads.val = reads.val + 1
    a.rect()
  })
  shown.get() |> ignore
  let first = reads.val
  // (moved nowhere; another one moved)
  a.pan(0.0, 0.0)
  b.pan(30.0, 0.0)
  shown.get() |> ignore
  assert_eq(reads.val, first)
  // (a small one kept centred in its stage, pushed against its edges, pinched by nothing: as it was, told nothing)
  let c = @kit.Zoom::new()
  c.natural(100.0, 100.0)
  c.boxed(400.0, 400.0)
  let c_reads = Ref(0)
  let c_shown = @signals.computed(fn(_) {
    c_reads.val = c_reads.val + 1
    c.rect()
  })
  c_shown.get() |> ignore
  c.pan(60.0, -20.0)
  c.transform(200.0, 200.0, 1.0, 0.0, 0.0)
  c_shown.get() |> ignore
  assert_eq(c_reads.val, 1)
  // (and moved: told)
  a.pan(30.0, 0.0)
  shown.get() |> ignore
  assert_eq(reads.val, first + 1)
}
