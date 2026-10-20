///|
test "a test finds words as a scripted run does, reads and pastes into the focused field, presses keys by name" {
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      c.text("Send it", wrap=false) |> ignore
      c.text("Send", wrap=false) |> ignore
      c.editor("field", placeholder="words") |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(t.locate("Send").length(), 2)
  assert_eq(t.locate("=Send").length(), 1)
  assert_eq(t.locate("nowhere"), [])
  assert_eq(t.size(), (390.0, 844.0))
  assert_eq(t.field_words(), "")
  t.tap_text("words")
  t.paste("pasted words")
  assert_eq(t.field_words(), "pasted words")
  assert_true(t.key_named("shift+enter"))
  assert_true(t.key_named("cmd+a"))
  assert_false(t.key_named("hyper+q"))
}

///|
test "a test sees the notifications the app shows, and taps one: what it opens is the app's, once" {
  let shown = Ref(false)
  let opened : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    if !shown.val {
      shown.val = true
      @ui.notice_show(channel="chats", tag="c1", title="Ana", body="the build is green", opens="chat:c1")
      @ui.notice_show(channel="chats", tag="c2", title="Lin", body="a question", opens="chat:c2")
      // the same tag again: the one before replaced
      @ui.notice_show(channel="chats", tag="c2", title="Lin", body="two questions", opens="chat:c2")
    }
    let o = @ui.notice_opened()
    if o != "" {
      opened.push(o)
    }
    c.text("app", wrap=false) |> ignore
  })
  t.draw()
  assert_eq(t.notices().map(fn(n) { n.body }), ["the build is green", "two questions"])
  assert_true(t.tap_notice("green"))
  assert_eq(opened, ["chat:c1"])
  assert_eq(t.notices().length(), 1)
  assert_false(t.tap_notice("green"))
  @ui.notice_cancel("c2")
  assert_eq(t.notices(), [])
}
