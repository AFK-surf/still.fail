// Laid out Small (a desktop's window under 600 wide: the phone's pages) pointed at with a mouse: the mouse's ways, as
// the wide frame has them, not a finger's (@ui.pointing), however narrow the window.

///|
test "small with a mouse: a chat's row right clicked opens its menu where it was clicked, the chat not opened" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0)
  assert_false(@sfdesk.is_wide(t.ctx()))
  let (x, y) = t.find("夜里的构建又失败了").unwrap()
  t.right_click(x, y)
  assert_true(t.find("复制会话链接") is Some(_), msg="\{t.drawn_text()}")
  assert_eq(app.nav.depth(), 1)
  // (a mouse holds nothing: no haptic)
  assert_eq(t.haptics(), [])
}

///|
test "small with a mouse: a chat's row held is no long press, a click that opens it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0)
  let (x, y) = t.find("夜里的构建又失败了").unwrap()
  t.press_at(x, y)
  t.run_for(@ui.tap_indication_ms + @sfpages.hold_ms)
  assert_true(t.find("复制会话链接") is None)
  t.release(x, y)
  t.run_for(@ui.move_most_ms)
  match app.nav.top() {
    Chat(r) => assert_eq(r.title, "夜里的构建又失败了")
    _ => fail("not opened")
  }
}

///|
test "small with a mouse: Enter sends what is typed (a keyboard at hand), as in the wide frame" {
  let calls : Array[Made] = []
  let t = fake_core(calls, platform=0)
  assert_false(@sfdesk.is_wide(t.ctx()))
  t.tap_text("发消息")
  t.type_text("第一行")
  t.enter()
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "text"), "第一行")
}
