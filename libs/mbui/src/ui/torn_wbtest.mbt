///|
/// The points of an outline (x, y, x, y, …) whose x is `x`.
fn torn_at(o : Array[Double], x : Double) -> Int {
  let mut n = 0
  for i = 0; i < o.length(); i = i + 2 {
    if (o[i] - x).abs() < 0.001 {
      n += 1
    }
  }
  n
}

///|
test "a ground torn at its end: three teeth there, their tips on its edge, its start round" {
  let o = torn_outline(30.0, 18.0, 6.0, false, true)
  let t = torn_tooth(18.0)
  assert_eq(t, 2.0)
  // the top's end and the teeth's four tips on the edge, the three notches a tooth in
  assert_eq(torn_at(o, 30.0), 4)
  assert_eq(torn_at(o, 28.0), 3)
  // the start round: only its arcs' ends touch x 0
  assert_eq(torn_at(o, 0.0), 2)
  assert_true(o.iter().all(fn(v) { v >= 0.0 && v <= 30.0 }))
}

///|
test "a ground torn at both ends: teeth either side, no corner round" {
  let o = torn_outline(30.0, 18.0, 6.0, true, true)
  assert_eq(torn_at(o, 28.0), 3)
  assert_eq(torn_at(o, 2.0), 3)
  assert_eq(torn_at(o, 0.0), 5)
}
