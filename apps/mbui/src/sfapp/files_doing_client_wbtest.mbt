///|
test "a folder keeps its operation state while the next folder loads" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture("home")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "doing" {
        let sub = client.follow_topic(name, params~)
        return { value: sub.value, error: sub.error, version: sub.version }
      }
      if name == "drive" && params.get("path") == Some(Json::string("设计稿")) {
        return { value: None, error: None, version: 0 }
      }
      (base.topic_read)(name, params)
    },
    waits: fn(name, params) {
      if name == "doing" { client.follow_topic(name, params~).waiting } else { (base.waits)(name, params) }
    },
    leave: fn(name, params, reason) {
      if reason is @sfbase.TopicLeave::Owned(stop) { stop(); return }
      if name == "doing" { client.leave_topic(name, params~) } else { (base.leave)(name, params, reason) }
    },
    release: fn(name, params) {
      if name == "doing" { client.release_topic(name, params~) } else { (base.release)(name, params) }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  app.nav.replace(Files)
  app.nav.push(Drive({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  t.run_for(@ui.move_most_ms)
  guard client.peek_topic("doing") is Some(sub) else { fail("the folder has no operation-state subscription") }
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "doing": [] } })
  t.frame()
  let (x, y) = rightmost(t, "设计稿")
  t.tap(x, y)
  t.tap(x, y)
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(t.find("配色说明.md") is None, msg="the next folder is still loading")
  assert_true(client.peek_topic("doing") is Some(current) && physical_equal(current, sub), msg="the original operation state stays subscribed")
  assert_eq(lease_ended(sent, sub.id), 0)
  @ui.run_let_go()
  assert_true(client.peek_topic("doing") is None, msg="the last folder reader releases operation state")
  assert_eq(lease_ended(sent, sub.id), 1)
}
