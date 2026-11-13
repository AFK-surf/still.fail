///|
/// Where come_way has it each ms from 0 to its end (come_way_ms), and how fast.
fn come_way_walk(from : Double, v : Double, goal : Double) -> Array[(Double, Double)] {
  let ms = come_way_ms(from, v, goal)
  let out = []
  let mut t = 0.0
  while t <= ms {
    out.push(come_way(from, v, goal, t))
    t = t + 1.0
  }
  out.push(come_way(from, v, goal, ms))
  out
}

///|
test "come_way set out toward where it goes: on from its speed all the way there, never slowed to rest on the way" {
  let walk = come_way_walk(100.0, 1.5, 300.0)
  assert_eq(walk[0], (100.0, 1.5))
  for i in 1..<(walk.length() - 1) {
    assert_true(walk[i].0 >= walk[i - 1].0, msg="back at \{i}: \{Repr(walk[i - 1])} \{Repr(walk[i])}")
  }
  // (no stall: fast till it is near, the speed at half way still a good share of what it set out at)
  let half = walk.search_by(fn(p) { p.0 >= 200.0 }).unwrap()
  assert_true(walk[half].1 > 0.3, msg="\{Repr(walk[half])}")
  assert_eq(walk[walk.length() - 1].0, 300.0)
}

///|
test "come_way turned back: on from its speed a little, slowing to rest, once, then to where it goes; its speed the same as it sets out" {
  let walk = come_way_walk(100.0, -0.6, 300.0)
  assert_eq(walk[0], (100.0, -0.6))
  let low = walk.iter().map(fn(p) { p.0 }).fold(init=100.0, fn(a, b) { if b < a { b } else { a } })
  // (carried on as far as a Move from that speed slows to rest: bounded)
  assert_true(low < 100.0 && low > 100.0 - move_stop_points(0.6) - 0.5, msg="\{low}")
  let mut turned = false
  for i in 1..<walk.length() {
    if walk[i].0 > walk[i - 1].0 {
      turned = true
    } else {
      assert_true(!turned || walk[i].0 == walk[i - 1].0, msg="down again at \{i}")
    }
  }
  assert_eq(walk[walk.length() - 1].0, 300.0)
}

///|
test "come_way set out a little toward where it goes and a little away from it: nearly the same way, as from rest" {
  let eps = 0.001
  for t in [0.0, 20.0, 60.0, 150.0, 250.0, 400.0] {
    let (up, _) = come_way(100.0, eps, 300.0, t)
    let (down, _) = come_way(100.0, -eps, 300.0, t)
    let (rest, _) = come_way(100.0, 0.0, 300.0, t)
    // (as far apart as that speed goes in the way's length: of the order of eps)
    let near = come_way_ms(100.0, 0.0, 300.0) * eps
    assert_true((up - down).abs() <= near && (up - rest).abs() <= near, msg="at \{t}: \{up} \{down} \{rest}")
  }
  // (as long, but for its slowing turned, all but none: as long as eps is of its gain then)
  assert_true(
    (come_way_ms(100.0, eps, 300.0) - come_way_ms(100.0, -eps, 300.0)).abs() <= come_way_ms(100.0, 0.0, 300.0) * eps,
  )
}

///|
/// A flight's way as words sent set out (at 50) and land (at 506): what goes with it (the room they open).
let come_with_flight : ComeWith = { start: 50.0, ends: 506.0 }

///|
test "come_way going with another way: set out as it does, there as it ends, a Move all the way, whatever how far" {
  let w = come_with_flight
  let ms = w.ends - w.start
  for far in [8.0, 64.0, 300.0] {
    assert_eq(come_way_ms(0.0, 0.0, far, along=w), ms)
    let mut was = 0.0
    let mut t = 0.0
    while t < ms {
      let (x, _) = come_way(0.0, 0.0, far, t, along=w)
      assert_true(x >= was && x <= far, msg="\{far} at \{t}: \{was} then \{x}")
      // (a Move as long as the flight: move_path over its length)
      let (off, _) = move_path(-far, 0.0, t, ms)
      assert_eq(x, far + off)
      was = x
      t = t + 1.0
    }
    assert_eq(come_way(0.0, 0.0, far, ms, along=w).0, far)
  }
}

///|
test "come_way going with another way, set off again at speed: on from it, there as that way ends" {
  let w = come_with_flight
  // (toward it already: a Move on from that speed, as long as the flight)
  assert_eq(come_way_ms(0.0, 0.3, 64.0, along=w), w.ends - w.start)
  assert_eq(come_way(0.0, 0.3, 64.0, 0.0, along=w), (0.0, 0.3))
  assert_eq(come_way(0.0, 0.3, 64.0, w.ends - w.start, along=w).0, 64.0)
  // (turned back: its slowing as ever, then to where it goes by the flight's end, no shorter than its slowing)
  let ms = come_way_ms(0.0, -0.3, 64.0, along=w)
  assert_eq(ms, w.ends - w.start)
  assert_eq(come_way(0.0, -0.3, 64.0, 0.0, along=w), (0.0, -0.3))
  assert_eq(come_way(0.0, -0.3, 64.0, ms, along=w).0, 64.0)
}

///|
test "come_way at speed toward where it goes, less than half a point from it: on from that speed on the least Move, never stopped dead" {
  // (alone: as long as the least Move, however near; its speed as it sets out the one it went at)
  assert_eq(come_way_ms(0.0, 0.3, 0.4), move_least_ms)
  assert_eq(come_way(0.0, 0.3, 0.4, 0.0), (0.0, 0.3))
  assert_eq(come_way_ms(0.0, -0.3, -0.4), move_least_ms)
  assert_eq(come_way(0.0, -0.3, -0.4, 0.0), (0.0, -0.3))
  assert_eq(come_way(0.0, 0.3, 0.4, move_least_ms).0, 0.4)
  // (going with another way: a Move on from it as long as that way, there as it ends)
  let w = come_with_flight
  assert_eq(come_way_ms(0.0, 0.3, 0.4, along=w), w.ends - w.start)
  assert_eq(come_way(0.0, 0.3, 0.4, 0.0, along=w), (0.0, 0.3))
  assert_eq(come_way(0.0, 0.3, 0.4, w.ends - w.start, along=w).0, 0.4)
  // (from rest, as near: there at once, no speed to lose)
  assert_eq(come_way_ms(0.0, 0.0, 0.4), 0.0)
}

///|
/// A way from 100 to 0 set out at `v`: where it is at each 60th of a second, 32 of them.
fn turned_frames(v : Double) -> Array[Double] {
  let out = []
  let mut t = 0.0
  while out.length() < 32 {
    out.push(come_way(100.0, v, 0.0, t).0)
    t = t + 1000.0 / 60.0
  }
  out
}

///|
test "come_way at speeds either way, a hundredth of a point a ms apart: the ways near, none taking another shape; from rest a Move to the bit" {
  // (in the place of the test of either side of where the slowing's share and its least speed met: no such place now,
  // any two speeds near each other going near ways)
  let ms = come_way_ms(100.0, 0.0, 0.0)
  let mut was = turned_frames(-0.2)
  let mut i = -19
  while i <= 20 {
    let v = i.to_double() / 100.0
    let now = turned_frames(v)
    let mut most = 0.0
    for k in 0..<now.length() {
      most = fmax(most, (now[k] - was[k]).abs())
    }
    // (no further apart than 13.5 points: 12.9 at the most, between 0 and 0.01 away, where how long it slows grows from
    // all but none (come_turn_w): its way back setting out later; a way going on, 0.15)
    assert_true(most <= 13.5, msg="\{v}: \{most}")
    was = now
    i = i + 1
  }
  let mut t = 0.0
  for x in turned_frames(0.0) {
    assert_eq(x, 0.0 + move_path(100.0, 0.0, t, ms).0)
    t = t + 1000.0 / 60.0
  }
}

///|
test "come_way turned back: slowing at one rate and its way back meet with its place, speed and gain going on; never past where it goes" {
  for c in [(345.0, 0.76, 0.0), (44.0, 0.3, 0.0), (10.0, 1.5, 0.0), (100.0, 0.08, 0.0), (100.0, 0.02, 0.0)] {
    let (from, v, goal) = c
    let tr = come_turned(v, goal - from, None)
    // (a thousandth of a ms each side: a finer step is a truer gain at the join itself, its way back's gain changing
    // fast as it sets out, so a hundredth of a ms off it the gain measured has already moved on by more than its 2%)
    let h = 0.001
    let at = fn(t : Double) { come_way(from, v, goal, t) }
    let (xa, va) = at(tr.t1 - h)
    let (xb, vb) = at(tr.t1 + h)
    assert_true((xa - xb).abs() < 0.01 && (va - vb).abs() <= 2.5 * h * tr.a + 1.0e-9, msg="\{Repr(c)}: \{xa} \{xb}, \{va} \{vb}")
    // (its gain each side: as it slowed, -a; as it sets back out, within what is taken off to rest at its end)
    let before = (at(tr.t1 - h).1 - at(tr.t1 - 2.0 * h).1) / h
    let after = (at(tr.t1 + 2.0 * h).1 - at(tr.t1 + h).1) / h
    assert_true((before - after).abs() <= 0.02 * tr.a + 1.0e-6, msg="\{Repr(c)}: gain \{before} then \{after}, a \{tr.a}")
    let mut t = 0.0
    while t <= come_way_ms(from, v, goal) {
      assert_true(at(t).0 >= goal - 1.0e-9, msg="\{Repr(c)} past \{goal} at \{t}: \{at(t).0}")
      t = t + 1.0
    }
    assert_eq(at(come_way_ms(from, v, goal)).0, goal)
  }
}

///|
/// How finely come_way's place is sampled about a moment (ms): its gain there as second differences.
let turn_gain_step : Double = 0.001

///|
test "come_way turned back: its gain goes on wherever it changes fastest as it slows and turns, its place sampled either side" {
  for c in [(345.0, 0.76, 0.0), (44.0, 0.3, 0.0), (10.0, 1.5, 0.0), (100.0, 0.08, 0.0), (100.0, 0.02, 0.0)] {
    let (from, v, goal) = c
    let h = turn_gain_step
    let x = fn(t : Double) { come_way(from, v, goal, t).0 }
    let gain = fn(t : Double) { (x(t + h) - 2.0 * x(t) + x(t - h)) / (h * h) }
    // (where its gain changes most in a ms, over the first half of its way, where it slows and turns, before it comes
    // to rest at its end as any Move does; then halved down to that change's place, four steps wide)
    let half = come_way_ms(from, v, goal) / 2.0
    let mut a = h * 4.0
    let mut most = -1.0
    let mut t = a
    while t + 1.0 < half {
      let change = (gain(t + 1.0) - gain(t)).abs()
      if change > most {
        most = change
        a = t
      }
      t = t + 1.0
    }
    let mut b = a + 1.0
    while b - a > 4.0 * h {
      let m = (a + b) / 2.0
      if (gain(m) - gain(a)).abs() >= (gain(b) - gain(m)).abs() {
        b = m
      } else {
        a = m
      }
    }
    // (its gain just before that and just after, each from its own side alone)
    let before = (x(a - h) - 2.0 * x(a - 2.0 * h) + x(a - 3.0 * h)) / (h * h)
    let after = (x(b + 3.0 * h) - 2.0 * x(b + 2.0 * h) + x(b + h)) / (h * h)
    assert_true(
      (before - after).abs() <= 0.02 * fmax(before.abs(), after.abs()) + 1.0e-6,
      msg="\{Repr(c)}: at \{a} ms, gain \{before} then \{after}",
    )
  }
}

///|
/// How far a way turned back slower than it can be seen (up to half turn_judged_from) may be from the way from rest at
/// any moment, as a share of how far it goes: a longer way goes faster, so the same small lag in setting out costs it
/// more points; as a share of its length it is the same at every length (2.3 to 2.4 hundredths at half
/// turn_judged_from, 43 points to 667; a tenth of that at a third less speed).
let turn_slow_share : Double = 0.03

///|
test "come_way turned back slower than it can be seen: nowhere further from the way from rest than three hundredths of its length" {
  for far in [43.0, 190.0, 345.0, 486.0, 667.0] {
    for i in 1..=50 {
      let v = turn_judged_from / 2.0 * i.to_double() / 50.0
      let end = fmax(come_way_ms(far, v, 0.0), come_way_ms(far, 0.0, 0.0))
      let mut t = 0.0
      while t <= end {
        let off = (come_way(far, v, 0.0, t).0 - come_way(far, 0.0, 0.0, t).0).abs()
        assert_true(off <= turn_slow_share * far, msg="\{far} at \{v}: \{off} off the way from rest at \{t} ms")
        t = t + 1.0
      }
    }
  }
}

///|
test "come_turn_w: a Move from rest's at rest, as far as its speed carries it fast" {
  assert_eq(come_turn_w(0.0), 1.0)
  assert_true(come_turn_w(0.76) < 0.005)
  assert_eq(come_turn_w(0.05), 0.5)
  assert_eq(come_turn_w(-0.05), come_turn_w(0.05))
}
