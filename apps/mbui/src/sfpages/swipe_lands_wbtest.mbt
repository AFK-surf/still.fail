///|
test "a row swiped left let go: archived landing past its line on from its speed, or flung from past half way; else back" {
  // (390 wide: its line 136.5 left)
  let s = @ui.move_stop_points(0.3)
  assert_false(swipe_archives(-135.5 + s, 390.0, -0.3))
  assert_true(swipe_archives(-137.5 + s, 390.0, -0.3))
  // (flung: faster than fling_speed, past half its line)
  assert_false(swipe_archives(-70.0, 390.0, -fling_speed + 0.01))
  assert_true(swipe_archives(-70.0, 390.0, -fling_speed - 0.01))
  assert_false(swipe_archives(-60.0, 390.0, -fling_speed - 0.01))
}
