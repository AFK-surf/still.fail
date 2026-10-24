// The wide frame on a tablet's screen (an opened fold's inner one: the system's size classes regular both ways), pointed
// at with a finger: the desktop's layout, the finger's hand (@ui.pointing).

///|
fn touch_wide_tester() -> @ui.Tester raise {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=860.0, h=950.0, platform=2)
  let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\nuntil 发消息\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  t
}

///|
test "touch wide: the desktop's frame, a chat's row held opens its menu (no right click there), the chat not opened" {
  let t = touch_wide_tester()
  assert_true(wide_on.val)
  let log = t.drive("hold 700 首页的列表改成按天分组\nuntil 复制会话链接\nuntil 归档\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  assert_true(
    match app.nav.top() {
      Chat(r) => r.session == "s-c1"
      _ => false
    },
  )
}

///|
test "touch wide: a row tapped is opened and left as it rests (a lifted finger hovers over nothing: no 归档 key on it)" {
  let t = touch_wide_tester()
  let log = t.drive("tap 首页的列表改成按天分组\nuntil 好的，我来处理\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  t.draw()
  assert_true(t.query(Button, label="归档「首页的列表改成按天分组」") is None)
}
