///|
test "scrolling an unchanged chat does not repeatedly read its topic" {
  new_run()
  let base = fixture("chat-long")
  let reads = Ref(0)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "chat" { reads.val += 1 }
      base.topic(name, params).get().snapshot()
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2, corners_held=false)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("发消息") is Some(_), msg="the chat is open")
  reads.val = 0
  t.drag(195.0, 260.0, 195.0, 560.0, steps=8)
  t.run_for(@ui.move_most_ms)
  println("CHAT_SCROLL_TOPIC_READS \{reads.val}")
  assert_true(reads.val <= 3, msg="scrolling without a chat change should not keep reading it: \{reads.val}")
}
