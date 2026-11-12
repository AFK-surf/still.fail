// A chat opened at a message older than what it first shows (a notification's, sfbase's chat_list.mbt go_tos): the
// pages before brought in (chat.older) until it is in the list, then the list at it, its top under the bar; the
// spinner over the first page going with the chat's last page moves nothing in view (each frame drawn: the Tester's
// rows_steady holds every row's place from one to the next).

///|
test "a chat opened at a message older than its first page: the pages before brought in, the list at the message under the bar, nothing jumping as the last comes" {
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  // (the page before's second message: seq -98, not among those the chat opens with)
  let words = "第 1 页之前的第 2 条：检查了构建脚本的第 4 步。"
  open_chat_at(r, -98.0)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  for _ in 0..<90 {
    t.run_for(@ui.frame_period_default)
  }
  guard t.find(words) is Some((_, y)) else { fail("not gone to: \{Repr(t.words().map(fn(w) { w.0 }))}") }
  // (its head's line, Claude and its time, under the bar: its words a line under that)
  assert_true(y > bar_foot() + 14.0 && y < 300.0, msg="\{y}")
  assert_true(t.find("做完了：列表、跳到最新的按钮、加载更早的消息都好了，截图也换了。") is None)
}
