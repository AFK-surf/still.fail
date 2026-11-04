///|
test "a chat waiting for its first messages is laid out on a medium touch screen" {
  let t = screen_in("chat-loading", corner_windows[1], "zh")
  assert_true(t.drawn_instances().length() > 0, msg="the waiting sample is drawn")
}
