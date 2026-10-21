// The framework asks for the frames inputs need (inputrec.mbt `took_input`, app.mbt `on_frame`), and for one asked
// between frames (Ctx::request_frame).

///|
test "every input asks the host for a frame, a key nothing under the pointer takes too" {
  let t = Tester::new(fn(c) { c.text("x") |> ignore }, w=100.0, h=100.0)
  t.draw()
  t.fake.wants = false
  // Enter with no field focused and no list under the pointer: before, nothing asked for a frame
  on_key(key_enter, 0)
  assert_true(t.fake.wants)
}

///|
test "the frame after an input is followed by one more, for what read it late" {
  let t = Tester::new(fn(c) { c.text("x") |> ignore }, w=100.0, h=100.0)
  t.draw()
  on_key(key_enter, 0)
  t.frame()
  assert_true(g().wants_frame)
  t.frame()
  assert_true(!g().wants_frame)
}

///|
test "a frame asked for between frames reaches the host" {
  let t = Tester::new(fn(c) { c.text("x") |> ignore }, w=100.0, h=100.0)
  t.draw()
  t.fake.wants = false
  g().request_frame()
  assert_true(t.fake.wants)
}

///|
test "run_for ends at the display's first frame at or past its end, though the host is asked for a frame each frame" {
  // (what asks the host for the next frame in every frame: a host's view playing, its state said each frame)
  let t = Tester::new(fn(c) {
      h_request_frame()
      c.text("x") |> ignore
    }, w=100.0, h=100.0)
  // a frame on: one frame, the display's next
  let next = t.next_frame_time()
  t.run_for(t.frame_period())
  assert_eq(t.time(), next)
  // five frames' time from here: the fifth frame on, none after it (what it owes is the next frame's)
  let from = t.time()
  t.run_for(5.0 * t.frame_period())
  assert_eq(t.time(), t.display_frame(from + 5.0 * t.frame_period()))
  assert_true(t.fake.wants)
}
