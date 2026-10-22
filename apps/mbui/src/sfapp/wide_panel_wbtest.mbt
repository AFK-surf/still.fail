// Beside a chat in the wide frame (wide_panel.mbt): its "…" a popover under its button, agent 往来 from it opened in the
// side panel at its right, the panel closed by its switch and opened again at the first agent's history.

///|
test "wide: the chat's \"…\" opens under its button; agent 往来 from it opens beside the chat; the panel closes and opens" {
  reset()
  let src = fixture("chat-letters-info")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.nav_push_ms)
  assert_true(wide_on.val)
  assert_true(t.find("agent 往来") is None)
  // what is done with it, under its "…": agent 往来 among it, saying how many
  t.click(Button, label="对话信息")
  t.frame()
  t.frame()
  assert_true(t.find("agent 往来") is Some(_))
  assert_true(t.find("4 条") is Some(_))
  assert_true(t.find("参与") is Some(_), msg="its facts")
  t.tap_text("agent 往来")
  // (the popover goes as a popover does: gone once its going is over)
  t.run_for(@kit.presence_out_ms)
  // beside the chat, at its right: the chats written with
  let (x, _) = t.find("接手监督 mbui").unwrap()
  assert_true(x > 800.0, msg="at the pane's right")
  assert_true(t.find("BFT 备份尺寸分析") is Some(_))
  assert_true(t.find("参与") is None, msg="the popover gone")
  // its switch closes it; the bar's opens it again, at the first agent's history
  t.click(Button, label="收起侧栏")
  t.frame()
  assert_true(t.find("接手监督 mbui") is None)
  t.click(Button, label="打开侧栏")
  t.frame()
  assert_true(t.find("步骤") is Some(_), msg="its history's tabs")
}
