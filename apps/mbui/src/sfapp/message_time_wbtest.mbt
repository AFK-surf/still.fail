// When a message was said (sfpages' message.mbt message_time): how long ago; pressed, every time in the chat says when
// instead, and pressed again how long ago once more.

///|
test "a message's time pressed: every time in the chat says when it was (10/19 …); pressed again, how long ago" {
  let t = chat_tester("chat")
  // (the last message's, msg 10: 5 分钟前, at 10/19 00:12:04)
  assert_true(t.find("5 分钟前") is Some(_))
  assert_true(t.find("10/19 00:12:04") is None)
  t.tap_text("5 分钟前")
  t.draw()
  assert_true(t.find("10/19 00:12:04") is Some(_))
  assert_true(t.find("5 分钟前") is None)
  // (the others too: msg 9's 15 分钟前)
  assert_true(t.find("15 分钟前") is None)
  t.tap_text("10/19 00:12:04")
  t.draw()
  assert_true(t.find("5 分钟前") is Some(_))
  assert_true(t.find("15 分钟前") is Some(_))
  assert_true(t.find("10/19 00:12:04") is None)
}
