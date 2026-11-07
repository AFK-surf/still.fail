///|
test "leaving an unobserved chat does not subscribe again, and reopening reads it" {
  new_run()
  let base = fixture("chat")
  let changed = @signals.signal(0)
  let left = Ref(false)
  let reopening = Ref(false)
  let after_leave = Ref(0)
  let after_reopen = Ref(0)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "chat" && text(Some(Json::object(params)), "session") == "s-c1" {
        changed.get() |> ignore
        if left.val {
          if reopening.val { after_reopen.val += 1 } else { after_leave.val += 1 }
        }
      }
      (base.topic)(name, params)
    },
    leave: fn(name, params) {
      if name == "chat" && text(Some(Json::object(params)), "session") == "s-c1" {
        left.val = true
        changed.set(changed.get() + 1)
      }
      (base.leave)(name, params)
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("发消息") is Some(_), msg="the chat is open")
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_true(left.val, msg="the page left the chat topic")
  assert_eq(after_leave.val, 0, msg="nothing asked for the chat after it was left")
  reopening.val = true
  open_chat(r)
  t.run_for(@ui.move_most_ms)
  assert_true(after_reopen.val > 0, msg="opening again reads the chat")
  assert_true(t.find("发消息") is Some(_), msg="the reopened chat is visible")
}
