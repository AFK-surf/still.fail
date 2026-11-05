///|
test "a place coming in is painted as it moves without building the old frame each time" {
  let t = tester("home")
  // Count host frames without the Tester's additional paint-verification builds.
  t.check_looks(false)
  t.set_frame_period(host_phone_period)
  t.run_for(first_page_ms + @ui.move_most_ms)
  to_bar_rest(t)
  let (xs, y) = bar_places_at()
  t.record_host()
  t.tap(xs[1], y)
  let end = place_switch.end()
  assert_true(end > t.time(), msg="the new place is moving")
  t.run_as_host(end - t.time())
  let frames = t.host_frames()
  assert_true(frames.length() > 2, msg="the move spans several host frames")
  let rebuilt : Array[String] = []
  for i, frame in frames {
    // The first frame handles the tap and builds the new place.
    if i > 0 && frame.at < end && frame.old_built {
      rebuilt.push(host_said(frame))
    }
  }
  assert_true(rebuilt.length() <= 1, msg="the old frame during the move: \{rebuilt}")
}
