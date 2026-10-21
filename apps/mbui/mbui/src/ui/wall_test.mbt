// The time of day for what is shown of it (wall.mbt): a Tester's as its test sets it, on with its frames' clock.

///|
test "a Tester's time of day: its own day at its start, on with its frames' clock, set by the test" {
  let minute = 60000.0
  // 3 minutes 20 seconds before the Tester's day begins
  let since = @ui.tester_wall - 3.0 * minute - 20000.0
  let shown : Ref[String] = Ref("")
  let t = @ui.Tester::new(fn(c) {
    let ago = ((@ui.wall_ms() - since) / minute).floor().to_int()
    shown.val = "\{ago} 分钟前"
    c.text(shown.val, wrap=false) |> ignore
    // its words change as the minute since `since` comes: a wake at it, counted from `since` (the wall's minute,
    // not the frames' clock's)
    c.every(minute, elapsed=@ui.wall_ms() - since) |> ignore
  })
  // a Tester's clock starts at 1000 (Tester::new's `time`): its day's at that moment
  let start = 1000.0
  assert_eq(@ui.wall_ms(), @ui.tester_wall - start + t.time())
  assert_eq(shown.val, "3 分钟前")
  // the minute turns at since + 4 minutes: the display's frame before it still says 3, its first frame at or past
  // it says 4
  let turn = since + 4.0 * minute - (@ui.tester_wall - start)
  let first = t.display_frame(turn)
  let before = first - @ui.frame_period_default
  t.run_for(before - t.time())
  assert_eq(t.time(), before)
  assert_eq(shown.val, "3 分钟前")
  assert_eq(@ui.wall_ms(), @ui.tester_wall - start + t.time())
  t.run_for(first - t.time())
  assert_eq(t.time(), first)
  assert_eq(shown.val, "4 分钟前")
  // set by the test: from then on
  t.set_wall(since + 10.0 * minute)
  assert_eq(@ui.wall_ms(), since + 10.0 * minute)
  t.draw()
  assert_eq(shown.val, "10 分钟前")
}
