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
    assert_true(walk[i].0 >= walk[i - 1].0, msg="back at \{i}: \{walk[i - 1]} \{walk[i]}")
  }
  // (no stall: fast till it is near, the speed at half way still a good share of what it set out at)
  let half = walk.search_by(fn(p) { p.0 >= 200.0 }).unwrap()
  assert_true(walk[half].1 > 0.3, msg="\{walk[half]}")
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
  assert_eq(come_way_ms(100.0, eps, 300.0), come_way_ms(100.0, -eps, 300.0))
}

///|
test "come_way turned back as fast either side of where its slowing's share and its least speed meet (0.4): nearly the same way" {
  for t in [0.0, 20.0, 60.0, 150.0, 250.0, 400.0] {
    let (a, _) = come_way(100.0, -0.399, 300.0, t)
    let (b, _) = come_way(100.0, -0.401, 300.0, t)
    // (as far apart as the speeds' difference goes in the way's length)
    let near = come_way_ms(100.0, -0.4, 300.0) * 0.002
    assert_true((a - b).abs() <= near, msg="at \{t}: \{a} \{b}")
  }
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
