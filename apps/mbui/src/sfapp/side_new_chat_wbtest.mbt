// 新建对话 over the sidebar's lists: its row all of the band's line the filter and the keys leave, pressed (and the
// pointer a hand) across it, as the web's NavTop row; not only over its icon and words.

///|
test "wide: 新建对话's row is pressed across the band's line, past its words: the pointer a hand there, a new chat opened" {
  for platform in [0, 2] {
    let calls : Array[Made] = []
    let t = wide_tester(calls, mode="chat", platform~)
    let (_, y) = t.find(@sf.t("web-main.sidebar.newChat")).unwrap()
    if platform == 0 {
      for x in [168.0, 216.0] {
        t.move(x, y)
        assert_eq(t.cursor(), Hand, msg="at \{(x, y)}")
      }
    }
    assert_false(app.nav.top() is NewChat)
    t.tap(216.0, y)
    t.frame()
    assert_true(app.nav.top() is NewChat, msg="platform \{platform}")
  }
}
