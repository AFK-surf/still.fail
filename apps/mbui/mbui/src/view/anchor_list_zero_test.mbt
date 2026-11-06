// Rows at a window edge can have no room for the first frame of a keyed move.

///|
test "zero-height rows at either anchored edge remain placed and keep the end" {
  let top_heights = [0.0, 0.0, 50.0, 50.0]
  let find = fn(k : Int, _near : Int) { if k >= 0 && k < 4 { Some(k) } else { None } }
  let top = list_laid_from_top(4, fn(i) { i }, find, fn(i) { top_heights[i] },
    Some({ key: 2, under: 0.0, near: 2 }), 300.0)
  assert_eq(top.keys, [0, 1, 2, 3])
  assert_eq(top.tops, [0.0, 0.0, 0.0, 50.0])
  assert_true(top.anchor is None)
  assert_true(top.at_end)

  let end_heights = [50.0, 50.0, 0.0, 0.0]
  let end = list_laid_from_end(4, fn(i) { i }, find, fn(i) { end_heights[i] },
    Some({ key: 1, under: 0.0, near: 1 }), 300.0)
  assert_eq(end.keys, [0, 1, 2, 3])
  assert_eq(end.tops, [200.0, 250.0, 300.0, 300.0])
  assert_true(end.anchor is None)
  assert_true(end.at_end)
}
