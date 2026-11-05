///|
test "leaving a long chat does not build the old root while the page moves away" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-long", w=390.0, h=844.0, platform=2, wrap=core_lists)
  t.set_frame_period(host_phone_period)
  t.run_for(@ui.move_most_ms)
  t.record_host()
  t.back_told(t.time())
  t.run_as_host(@ui.move_most_ms)
  let rebuilt : Array[String] = []
  for i, frame in t.host_frames() {
    // The first frame takes the back action; the later frames move the page away.
    if i > 0 && frame.old_built {
      rebuilt.push(host_said(frame))
    }
  }
  assert_eq(rebuilt, [])
}

///|
test "leaving a chat tells its departure and releases it without a test-supplied frame" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-long", w=390.0, h=844.0, platform=2, wrap=core_lists)
  t.set_frame_period(host_phone_period)
  t.run_for(@ui.move_most_ms)
  let left = @sfbase.left_said.get()
  t.record_host()
  t.back_told(t.time())
  t.run_as_host(@ui.move_most_ms)
  assert_eq(@sfbase.left_said.get(), left + 1)
  assert_eq(@sfbase.left_pages.length(), 0)
  let departures = named(calls, "client.focus").filter(fn(m) { field(Some(m.params), "left") is Some(_) })
  assert_eq(departures.length(), 1)
  assert_true(readings.get("ws1/st1\u{1}s-c1") is None)
}
