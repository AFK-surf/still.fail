///|
test "the one pulled over on the tape let go: over landing past its share on from its speed, or flung toward it; back flung away" {
  // (its way 400 over: its share 120)
  let s = @ui.move_stop_points(0.3)
  assert_false(tape_goes_over(119.0 - s, 400.0, 300.0))
  assert_true(tape_goes_over(121.0 - s, 400.0, 300.0))
  assert_false(tape_goes_over(-119.0 + s, -400.0, -300.0))
  assert_true(tape_goes_over(-121.0 + s, -400.0, -300.0))
  // (flung: faster than tape_fling, toward it over however short, away back however far)
  assert_false(tape_goes_over(20.0, 400.0, tape_fling - 1.0))
  assert_true(tape_goes_over(20.0, 400.0, tape_fling + 1.0))
  assert_false(tape_goes_over(200.0, 400.0, -tape_fling - 1.0))
}
