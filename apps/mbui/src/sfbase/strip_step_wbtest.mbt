///|
test "a picture's strip let go: on to the one beside it landing far enough on from its speed, or flung from its edge; else back" {
  // (a picture 390 wide: far 78)
  let s = @ui.move_stop_points(0.2)
  assert_eq(strip_step(-77.0 + s, -0.2, 390.0, false), 0)
  assert_eq(strip_step(-79.0 + s, -0.2, 390.0, false), 1)
  assert_eq(strip_step(77.0 - s, 0.2, 390.0, false), 0)
  assert_eq(strip_step(79.0 - s, 0.2, 390.0, false), -1)
  // (flung from its edge: faster than 0.3, past 10)
  assert_eq(strip_step(-20.0, -0.29, 390.0, true), 0)
  assert_eq(strip_step(-20.0, -0.31, 390.0, true), 1)
  assert_eq(strip_step(-20.0, -0.31, 390.0, false), 0)
}
