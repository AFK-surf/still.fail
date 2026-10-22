///|
test "a page left lets go of what it read that no page still there reads (Compose's rememberTopic leaving)" {
  reset()
  let base = fixture("chat")
  let read : Map[String, Bool] = {}
  let left : Array[String] = []
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      read[name] = true
      (base.topic)(name, params)
    },
    leave: fn(name, params) { left.push(name + " " + Json::object(params).stringify()) },
  }
  let r = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  // Home first, then the chat over it
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.draw()
  open_chat(r)
  t.run_for(@ui.nav_push_ms)
  assert_true(read.contains("chatJobs"))
  assert_eq(left, [])
  t.back()
  t.run_for(@ui.nav_push_ms)
  let held = Json::object(chat_params(r)).stringify()
  // its view and its jobs (else the core keeps the thread's window as first read: the chat opened again where it was
  // first opened, not where it was left), once each
  assert_eq(left.filter(fn(l) { l == "chat " + held }).length(), 1)
  assert_eq(left.filter(fn(l) { l == "chatJobs " + held }).length(), 1)
  // what Home and the app still read, kept
  assert_true(!left.iter().any(fn(l) { l.has_prefix("chats ") || l.has_prefix("prefs ") || l.has_prefix("workspaces ") }))
}
