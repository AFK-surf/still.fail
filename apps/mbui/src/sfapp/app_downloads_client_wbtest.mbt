// Downloads are watched by the application independently of which page is visible.

///|
fn app_downloads_lifetime(legacy : Bool) -> Unit raise {
  new_run()
  let sent : Array[String] = []
  let taken : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture_app("home")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name != "downloads" { return (base.topic_read)(name, params) }
      let sub = client.follow_topic(name, params~)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, params) {
      if name == "downloads" { client.follow_topic(name, params~).waiting } else { (base.waits)(name, params) }
    },
    leave: fn(name, params, reason) {
      if reason is @sfbase.TopicLeave::Owned(stop) { stop(); return }
      if name == "downloads" { client.leave_topic(name, params~) } else { (base.leave)(name, params, reason) }
    },
    release: fn(name, params) {
      if name == "downloads" { client.release_topic(name, params~) } else { (base.release)(name, params) }
    },
    call: fn(name, args, done) {
      if name == "download.take" {
        taken.push(@sfbase.text(Some(args), "id"))
        done(Ok({ "taken": false }))
      } else {
        (base.call)(name, args, done)
      }
    },
  }
  let old = if legacy { Some(@signals.untracked(fn() { client.follow_topic("downloads") })) } else { None }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(first_page_ms + @ui.move_most_ms)
  guard client.peek_topic("downloads") is Some(sub) else { fail("the app has no downloads reader") }
  if old is Some(previous) { assert_true(physical_equal(previous, sub)) }
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "downloads": [] } })
  t.frame()
  open_chat_beside({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  t.run_for(@ui.move_most_ms)
  assert_true(client.peek_topic("downloads") is Some(s) && physical_equal(s, sub), msg="opening a page must keep the app's original downloads reader")
  assert_eq(lease_ended(sent, sub.id), 0)
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "downloads": [{ "id": "ready-one", "state": "ready", "title": "file.txt" }] } })
  t.frame()
  assert_eq(taken, ["ready-one"], msg="the app handles a completed download while a chat is shown")
  home()
  t.run_for(@ui.move_most_ms)
  assert_true(client.peek_topic("downloads") is Some(s) && physical_equal(s, sub), msg="returning home must keep the app's original downloads reader")
  assert_eq(lease_ended(sent, sub.id), 0)
  @ui.run_let_go()
  if old is Some(previous) {
    assert_true(client.peek_topic("downloads") is Some(s) && physical_equal(s, previous), msg="the legacy reader outlives the host")
    client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "downloads": [], "marker": "after host" } })
    assert_eq(@sfbase.text(previous.value, "marker"), "after host")
    client.leave_topic("downloads")
  }
  assert_true(client.peek_topic("downloads") is None, msg="the last reader releases downloads")
  let subscribes = sent.filter(fn(s) {
    let msg = try Some(@json.parse(s)) catch { _ => None }
    @sfbase.text(@sfbase.field(msg, "subscribe"), "topic") == "downloads"
  })
  assert_eq(subscribes.length(), 1, msg="the app did not subscribe twice")
  assert_eq(lease_ended(sent, sub.id), 1, msg="the original subscription ends once")
}

///|
test "the app keeps downloads across pages until its host ends" {
  app_downloads_lifetime(false)
}

///|
test "the app releases downloads without ending an independent legacy reader" {
  app_downloads_lifetime(true)
}
