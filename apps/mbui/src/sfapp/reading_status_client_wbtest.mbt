// The reading splash follows the global status only while the splash is part of the application tree.

///|
fn reading_status_lifetime(legacy : Bool) -> Unit raise {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture("landing")
  let workspaces = @signals.signal(reading_topic(), same=fn(a, b) { physical_equal(a, b) })
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "workspaces" { return workspaces.get() }
      if name != "status" || !params.is_empty() { return (base.topic_read)(name, params) }
      let sub = client.follow_topic(name, params~)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, params) {
      if name == "status" && params.is_empty() { client.follow_topic(name, params~).waiting } else { (base.waits)(name, params) }
    },
    leave: fn(name, params, reason) {
      if reason is @sfbase.TopicLeave::Owned(stop) { stop(); return }
      if name == "status" && params.is_empty() { client.leave_topic(name, params~) } else { (base.leave)(name, params, reason) }
    },
    release: fn(name, params) {
      if name == "status" && params.is_empty() { client.release_topic(name, params~) } else { (base.release)(name, params) }
    },
  }
  let old = if legacy { Some(@signals.untracked(fn() { client.follow_topic("status") })) } else { None }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.check_looks(false)
  t.run_for(splash_label_ms)
  guard client.peek_topic("status") is Some(original) else { fail("the reading splash did not follow status") }
  if old is Some(previous) { assert_true(physical_equal(previous, original)) }
  client.receive_json({ "id": Json::number(original.id.to_double()), "value": { "lines": ["Connecting to the test station"] } })
  t.frame()
  assert_true(t.find("Connecting to the test station") is Some(_), msg="the reading splash shows the status value")
  assert_eq(lease_ended(sent, original.id), 0)
  workspaces.set({
    value: Some([{ "account": { "sub": "u1", "email": "lin@example.com", "name": "林" }, "workspaces": [], "invitations": [], "loaded": true }]),
    error: None,
    version: 3,
  })
  t.frame()
  assert_true(t.find("尚未加入任何 workspace") is Some(_), msg="the landing replaced the reading splash")
  assert_true(t.find("Connecting to the test station") is None, msg="the reading splash is gone")
  if old is Some(previous) {
    assert_true(client.peek_topic("status") is Some(s) && physical_equal(s, previous), msg="the independent reader survives the splash")
    assert_eq(lease_ended(sent, original.id), 0)
    client.receive_json({ "id": Json::number(original.id.to_double()), "value": { "marker": "after splash" } })
    assert_eq(@sfbase.text(previous.value, "marker"), "after splash")
    client.leave_topic("status")
  }
  assert_true(client.peek_topic("status") is None, msg="the last status reader has left")
  let subscribes = sent.filter(fn(s) {
    let msg = try Some(@json.parse(s)) catch { _ => None }
    @sfbase.text(@sfbase.field(msg, "subscribe"), "topic") == "status"
  })
  assert_eq(subscribes.length(), 1)
  assert_eq(lease_ended(sent, original.id), 1)
  @ui.run_let_go()
}

///|
test "the reading splash releases its global status when landing replaces it" {
  reading_status_lifetime(false)
}

///|
test "the reading splash leaves an independent global status reader intact" {
  reading_status_lifetime(true)
}
