// A chat's mark coming while its row shows pops in (chat_mark.mbt pop_scale): from nothing to 1.3 at 60% of its
// 320 ms, then down to its size, never past 1.3 nor under nothing on the way.

///|
test "a mark's pop: nothing at its start, 1.3 at 60% of its way, its own size at its end, rising then settling" {
  assert_eq(pop_scale(0.0), 0.0)
  assert_true((pop_scale(mark_pop_peak_at) - mark_pop_peak).abs() < 1.0e-9)
  assert_true((pop_scale(1.0) - 1.0).abs() < 1.0e-9)
  let mut was = 0.0
  for i in 1..=60 {
    let v = i.to_double() / 100.0
    assert_true(pop_scale(v) >= was, msg="rising at \{v}")
    was = pop_scale(v)
  }
  for i in 61..=100 {
    let v = i.to_double() / 100.0
    assert_true(pop_scale(v) <= was + 1.0e-9 && pop_scale(v) >= 1.0 - 1.0e-9, msg="settling at \{v}")
    was = pop_scale(v)
  }
}
