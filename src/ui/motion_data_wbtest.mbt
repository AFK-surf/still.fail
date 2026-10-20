// Motion as data (motion_data.mbt): a spring solved, its end said once.

///|
test "a spring solved comes to rest by the end it said, and is still at it" {
  for c in [(420.0, 32.0), (260.0, 24.0), (100.0, 20.0), (100.0, 40.0)] {
    let (k, d) = c
    for x0 in [1.0, -300.0, 0.25] {
      let end = spring_end(x0, 0.0, k, d, 0.001)
      let (x, v) = spring_at(x0, 0.0, k, d, end)
      assert_true(x.abs() < 0.001 && v.abs() < 0.001)
      // and it was not there long before (the end is not far too late: within a factor of two)
      let (x2, v2) = spring_at(x0, 0.0, k, d, end / 2.0)
      assert_true(x2.abs() >= 0.000001 || v2.abs() >= 0.000001)
    }
  }
}

///|
test "a spring's frames are drawn until its end, then none; retargeted, it goes on as fast as it went" {
  let target = Ref::new(0.0)
  let seen = Ref::new(0.0)
  let t = Tester::new(fn(c) { seen.val = c.spring("x", target.val, from=0.0) }, w=100.0, h=100.0)
  t.assert_idle()
  target.val = 100.0
  t.draw()
  // the spring's own end (its way said as it set out)
  let end = fn() { g().springs.values().fold(init=-1.0, fn(e, s) { if s.end() > e { s.end() } else { e } }) }
  assert_true(end() > t.time())
  // a moment mid-way
  let mid_way = 50.0
  t.run_for(mid_way)
  let mid = seen.val
  assert_true(mid > 0.0 && mid < 100.0)
  // a new target mid-way: from where it is, not from rest
  target.val = 50.0
  t.draw()
  assert_true((seen.val - mid).abs() < 0.000001)
  t.run_for(end() - t.time())
  assert_true((seen.val - 50.0).abs() < 0.001)
  t.assert_idle()
}

///|
test "a spring sent on the frame's own clock: go_at and value_at are go and value at that frame's time" {
  let p = SpringPath::new(0.0, k=420.0, c=32.0)
  let q = SpringPath::new(0.0, k=420.0, c=32.0)
  let seen = Ref(0.0)
  let t = Tester::new(fn(c) {
    if p.target() == 0.0 {
      p.go_at(c, 100.0)
      q.go(c.now(), 100.0)
    }
    seen.val = p.value_at(c)
  })
  t.draw()
  // a moment mid-way
  let mid_way = 40.0
  t.run_for(mid_way)
  assert_eq(seen.val, q.value(t.time()))
  assert_eq(p.end(), q.end())
}

///|
test "every from when its count started: the next period's frame where the count changes, not the clock's own seconds" {
  let second = 1000.0
  let begin : Ref[Double] = Ref(-1.0)
  let started : Ref[Double] = Ref(-1.0)
  let shown : Ref[Int] = Ref(-1)
  let t = Tester::new(fn(c) {
    if begin.val < 0.0 {
      begin.val = c.now()
    }
    // a run that starts 600 ms after the first frame, counting its seconds from then
    if started.val < 0.0 && c.now() >= begin.val + 600.0 {
      started.val = c.now()
    }
    if started.val >= 0.0 {
      shown.val = c.every(second, from=started.val)
      c.text("\{shown.val} s", wrap=false) |> ignore
    }
  })
  t.draw()
  t.run_for(begin.val + 600.0 - t.time())
  let s0 = begin.val + 600.0
  assert_eq(started.val, s0)
  assert_eq(shown.val, 0)
  // its frame is asked for at 1600 ms after, then 2600: where what it shows changes
  assert_eq(g().wake_at, s0 + 1000.0)
  // a millisecond short of its first second, then that second
  let short = second - 1.0
  t.run_for(short)
  assert_eq(shown.val, 0)
  t.run_for(second - short)
  assert_eq(shown.val, 1)
  assert_eq(g().wake_at, s0 + 2000.0)
  t.run_for(second)
  assert_eq(shown.val, 2)
  assert_eq(g().wake_at, s0 + 3000.0)
  t.assert_idle()
}

///|
test "every by how far a count kept on another clock is: its frame where that count's next period starts" {
  let second = 1000.0
  let shown : Ref[Int] = Ref(-1)
  // a run that had gone 4300 ms when the test began (its own clock: the station's), counted on as the frames go
  let t = Tester::new(fn(c) {
    shown.val = c.every(second, elapsed=4300.0 + c.now())
    c.text("\{shown.val} s", wrap=false) |> ignore
  })
  t.draw()
  let t0 = t.time()
  assert_eq(shown.val, ((4300.0 + t0) / second).floor().to_int())
  // its next second where the run's is, not the frames' clock's own
  assert_eq(g().wake_at, t0 + 1000.0 - (4300.0 + t0 - 1000.0 * ((4300.0 + t0) / 1000.0).floor()))
  t.assert_idle()
}
