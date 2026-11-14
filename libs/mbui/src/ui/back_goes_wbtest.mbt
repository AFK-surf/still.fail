///|
test "a page drawn back let go: back landing past a third or back_far on from its speed, or flung; else not" {
  let s = move_stop_points(0.3)
  // (a phone's 390: a third 130, back_far 120 the nearer)
  assert_false(back_goes(119.0 - s, 390.0, 0.3))
  assert_true(back_goes(121.0 - s, 390.0, 0.3))
  // (a wide one: a third of 300 is 100, nearer than back_far)
  assert_false(back_goes(99.0 - s, 300.0, 0.3))
  assert_true(back_goes(101.0 - s, 300.0, 0.3))
  // (flung: past 40, faster than 0.6)
  assert_false(back_goes(41.0, 390.0, 0.59))
  assert_true(back_goes(41.0, 390.0, 0.61))
  assert_false(back_goes(39.0, 390.0, 0.61))
  // (going the other way as let go: landing short of where it was)
  assert_false(back_goes(125.0, 390.0, -0.3))
}
