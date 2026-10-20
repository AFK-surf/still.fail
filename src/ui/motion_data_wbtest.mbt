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
