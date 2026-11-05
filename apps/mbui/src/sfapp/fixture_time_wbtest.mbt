// A made-up core's replies are inputs at their declared moments, even when
// no picture was requested between them. Drawing cannot deliver a reply late.

///|
test "fixture replies keep their cause times and order when the supplied clock skips frames" {
  for dense in [false, true] {
    new_run()
    let clock = Ref(1000.0)
    fix_clock.val = Some(fn() { clock.val })
    let seen : Array[(Int, Double)] = []
    // Registered out of order, with a reply that schedules another reply.
    fix_later(200.0, fn() { seen.push((2, clock.val)) })
    fix_later(100.0, fn() {
      seen.push((1, clock.val))
      fix_later(50.0, fn() { seen.push((3, clock.val)) })
    })
    if dense {
      for at in [1050.0, 1100.0, 1150.0, 1200.0] { fix_clock_set(clock, at) }
    }
    fix_clock_set(clock, 1300.0)
    assert_eq(seen, [(1, 1100.0), (3, 1150.0), (2, 1200.0)])
    assert_eq(clock.val, 1300.0)
  }
}

///|
test "a later input delivers due fixture replies at their own moments without a drawn frame" {
  let t = wide_tester([], mode="chat", w=390.0, h=844.0, platform=2)
  let tree = @ui.view_tree().unwrap()
  let start = tree.logic_at()
  let seen : Array[Double] = []
  fix_later(100.0, fn() {
    seen.push(tree.logic_at())
    fix_later(50.0, fn() { seen.push(tree.logic_at()) })
  })
  t.record_host()
  t.touch_at(0, -100.0, -100.0, start + 300.0)
  assert_eq(seen, [start + 100.0, start + 150.0])
  assert_eq(t.host_frames().length(), 0)
  t.touch_at(2, -100.0, -100.0, start + 300.0)
}
