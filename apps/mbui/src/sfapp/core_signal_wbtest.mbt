// A real core client's messages reach the app's signal without a frame or a page copying its fields.

///|
test "a frame hands a topic between readers without resubscribing and releases it when none remain" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let phase = Ref(0)
  let seen = Ref("")
  let first = @signals.watch(fn() {  })
  let second = @signals.watch(fn() {  })
  let t = @ui.Tester::new(fn(_) {
    if phase.val == 0 {
      first.read(fn() { seen.val = @sfbase.text(src.topic("doing", {}).get().value, "text") })
    } else if phase.val == 1 {
      first.stop()
      second.read(fn() { seen.val = @sfbase.text(src.topic("doing", {}).get().value, "text") })
    } else {
      second.stop()
    }
  })
  t.draw()
  let sub = client.peek_topic("doing").unwrap()
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "text": "kept" } })
  sent.clear()
  phase.val = 1
  t.stepped()
  t.draw()
  assert_true(physical_equal(sub, client.peek_topic("doing").unwrap()), msg="the next reader kept the subscription")
  assert_eq(seen.val, "kept")
  assert_eq(sent.length(), 0, msg="the frame handover did not unsubscribe or subscribe")
  phase.val = 2
  t.stepped()
  t.draw()
  assert_true(client.peek_topic("doing") is None, msg="the frame released its last reader")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "ending a run releases its last frame reader without drawing another frame" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let t = @ui.Tester::new(fn(_) { src.topic("doing", {}).get() |> ignore })
  t.draw()
  assert_true(client.peek_topic("doing") is Some(_))
  sent.clear()
  @ui.run_let_go()
  assert_true(client.peek_topic("doing") is None, msg="the stopped run has no subscription")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
fn wide_chat_subscription_case(intermediate : Bool, leave_pending : Bool) -> Unit raise {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture_app("home")
  let chat : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let params = @sfbase.chat_params(chat)
  let core_params = @sfbase.core_topic_params("chat", params)
  let src : Source = {
    ..base,
    topic_read: fn(name, p) {
      if name != "chat" { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=@sfbase.core_topic_params(name, p))
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) {
      if name == "chat" { client.follow_topic(name, params=@sfbase.core_topic_params(name, p)).waiting } else { (base.waits)(name, p) }
    },
    leave: fn(name, p) {
      if name == "chat" { client.leave_topic(name, params=@sfbase.core_topic_params(name, p)) } else { (base.leave)(name, p) }
    },
    release: fn(name, p) {
      if name == "chat" { client.release_topic(name, params=@sfbase.core_topic_params(name, p)) } else { (base.release)(name, p) }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.frame()
  sent.clear()
  let opened_at = t.time()
  open_chat_beside(chat)
  t.frame()
  guard client.peek_topic("chat", params=core_params) is Some(sub) else { fail("opening did not subscribe to the chat: \{sent}") }
  assert_eq(sent.length(), 1, msg="the waiting pane keeps its first chat subscription: \{sent}")
  let opened = try Some(@json.parse(sent[0])) catch { _ => None }
  assert_eq(@sfbase.text(@sfbase.field(opened, "subscribe"), "topic"), "chat")
  assert_eq(@sfbase.number(opened, "id"), sub.id.to_double())
  t.frame()
  assert_true(physical_equal(sub, client.peek_topic("chat", params=core_params).unwrap()))
  assert_eq(sent.length(), 1, msg="waiting another frame does not replace the subscription")
  if intermediate { t.frame_at(opened_at + 50.0) }
  t.frame_at(opened_at + 100.0)
  assert_true(t.shown_of("截图也换了") is None, msg="the chat's message has not appeared before its answer")
  let answered = if leave_pending {
    // Replace the pane before its answer. Reopening must create a new owner; a late reply to the old id is ignored.
    @sfbase.nav_over_home([])
    t.frame_at(opened_at + 116.0)
    t.frame_at(opened_at + 132.0)
    assert_true(client.peek_topic("chat", params=core_params) is None, msg="leaving while waiting releases the chat")
    assert_eq(sent.length(), 2, msg="leaving while waiting sends one unsubscribe: \{sent}")
    let left = try Some(@json.parse(sent[1])) catch { _ => None }
    assert_true(@sfbase.flag(left, "unsubscribe"))
    assert_eq(@sfbase.number(left, "id"), sub.id.to_double())
    open_chat_beside(chat)
    t.frame_at(opened_at + 148.0)
    guard client.peek_topic("chat", params=core_params) is Some(reopened) else { fail("reopening did not subscribe: \{sent}") }
    assert_true(reopened.id != sub.id, msg="the reopened chat has a new subscription")
    assert_eq(sent.length(), 3, msg="reopening subscribes once: \{sent}")
    let reopened_message = try Some(@json.parse(sent[2])) catch { _ => None }
    assert_eq(@sfbase.text(@sfbase.field(reopened_message, "subscribe"), "topic"), "chat")
    assert_eq(@sfbase.number(reopened_message, "id"), reopened.id.to_double())
    let before_late = (reopened.value, reopened.error, reopened.version, reopened.waiting)
    // Deliberately distinct from the actual chat answer, so a stale delivery cannot masquerade as that answer.
    client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "lateOnly": "old subscription" } })
    t.frame_at(opened_at + 164.0)
    assert_eq((reopened.value, reopened.error, reopened.version, reopened.waiting), before_late, msg="the old reply did not change the new subscription")
    assert_true(t.shown_of("截图也换了") is None, msg="a reply for the released id cannot fill the reopened chat")
    reopened
  } else {
    sub
  }
  let value = (base.topic_read)("chat", params).value.unwrap()
  let answered_at = t.time()
  client.receive_json({ "id": Json::number(answered.id.to_double()), "value": value })
  t.frame_at(answered_at + 16.0)
  assert_eq(answered.value, Some(value), msg="the reopened subscription received the new answer")
  if intermediate { t.frame_at(answered_at + 40.0) }
  // Sample the same point after the answer whether or not an intermediate frame was drawn.
  t.frame_at(answered_at + 80.0)
  guard t.shown_of("截图也换了") is Some((_, _, w, h)) && w > 0.0 && h > 0.0 else {
    fail("the first answer's message is outside the visible area")
  }
  assert_true(t.words().iter().any(fn(word) { word.0.contains("截图也换了") && word.5 > 0.0 }), msg="the first answer's message is not transparent")
  @sfbase.nav_over_home([])
  t.frame()
  t.frame()
  assert_true(client.peek_topic("chat", params=core_params) is None, msg="the chat is released when the pane leaves")
  let n = if leave_pending { 4 } else { 2 }
  assert_eq(sent.length(), n, msg="the chat is unsubscribed once after leaving: \{sent}")
  let last = try Some(@json.parse(sent[n - 1])) catch { _ => None }
  assert_true(@sfbase.flag(last, "unsubscribe"))
  assert_eq(@sfbase.number(last, "id"), answered.id.to_double())
  @ui.run_let_go()
}

///|
test "opening a wide chat keeps its first subscription until its answer with or without intermediate frames" {
  wide_chat_subscription_case(false, false)
  wide_chat_subscription_case(true, false)
}

///|
test "a wide chat left before its answer releases it and reopens on a new subscription" {
  wide_chat_subscription_case(false, true)
  wide_chat_subscription_case(true, true)
}

///|
test "home releases transfers while a chat covers it and reads current transfers on return" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture_app("home")
  let params : Map[String, Json] = { "workspace": Json::string("ws1") }
  let src : Source = {
    ..base,
    topic_read: fn(name, p) {
      if name != "driveTransfers" { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=p)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) {
      if name == "driveTransfers" { client.follow_topic(name, params=p).waiting } else { (base.waits)(name, p) }
    },
    leave: fn(name, p) {
      if name == "driveTransfers" { client.leave_topic(name, params=p) } else { (base.leave)(name, p) }
    },
    release: fn(name, p) {
      if name == "driveTransfers" { client.release_topic(name, params=p) } else { (base.release)(name, p) }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.frame()
  guard client.peek_topic("driveTransfers", params~) is Some(first) else { fail("home did not subscribe to transfers") }
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": { "transfers": [{ "active": true, "copied": 25, "total": 100 }] } })
  t.frame()
  assert_true(t.query(Button, label="1 个传输 · 25%") is Some(_), msg="home shows the transfer")
  let covered_at = t.time()
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  t.frame()
  // The 390-point page slide's declared boundary is relative to the open event, independent of intermediate frames.
  let cover_boundary = covered_at + @ui.move_ms(390.0)
  t.frame_at(cover_boundary - 1.0)
  assert_true(client.peek_topic("driveTransfers", params~) is Some(_), msg="home still reads transfers just before it is covered")
  t.frame_at(cover_boundary)
  t.frame()
  assert_true(t.shown_of("做完了：") is Some(_), msg="the chat covers home")
  assert_true(client.peek_topic("driveTransfers", params~) is None, msg="home no longer reads transfers")
  let returned_at = t.time()
  nav_home()
  t.frame()
  t.frame_at(returned_at + @ui.move_ms(390.0))
  t.frame()
  guard client.peek_topic("driveTransfers", params~) is Some(second) else { fail("home did not resubscribe on return") }
  assert_true(second.id != first.id)
  client.receive_json({ "id": Json::number(second.id.to_double()), "value": { "transfers": [{ "active": true, "copied": 60, "total": 100 }] } })
  t.frame()
  assert_true(t.query(Button, label="1 个传输 · 60%") is Some(_), msg="home shows the current transfer")
  client.receive_json({ "id": Json::number(second.id.to_double()), "delta": [{ "path": ["transfers", 0, "copied"], "set": 75 }] })
  t.frame()
  assert_true(t.query(Button, label="1 个传输 · 75%") is Some(_), msg="home follows later transfer updates")
  @ui.run_let_go()
  assert_true(client.peek_topic("driveTransfers", params~) is None)
}

///|
test "reopening a chat reads the current station and follows later updates" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture_app("home")
  let params : Map[String, Json] = { "scope": "ws1" }
  let src : Source = {
    ..base,
    topic_read: fn(name, p) {
      if name != "stations" { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=p)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) {
      if name == "stations" { client.follow_topic(name, params=p).waiting } else { (base.waits)(name, p) }
    },
    leave: fn(name, p) {
      if name == "stations" { client.leave_topic(name, params=p) } else { (base.leave)(name, p) }
    },
    release: fn(name, p) {
      if name == "stations" { client.release_topic(name, params=p) } else { (base.release)(name, p) }
    },
  }
  let chat : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_chat(chat)
  t.frame()
  guard client.peek_topic("stations", params~) is Some(first) else { fail("the chat did not subscribe to stations") }
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": [{ "station": "ws1/st1", "name": "Cedar" }] })
  t.frame()
  assert_true(t.shown_of("Cedar") is Some(_), msg="the chat shows its station")
  let left_at = t.time()
  nav_home()
  t.frame()
  let leave_boundary = left_at + @ui.move_ms(390.0)
  t.frame_at(leave_boundary - 1.0)
  assert_true(client.peek_topic("stations", params~) is Some(_), msg="the leaving chat still reads stations before its boundary")
  t.frame_at(leave_boundary)
  t.frame()
  assert_true(client.peek_topic("stations", params~) is None, msg="the chat released stations on leaving")
  open_chat(chat)
  t.frame()
  guard client.peek_topic("stations", params~) is Some(second) else { fail("the reopened chat did not subscribe to stations") }
  assert_true(second.id != first.id)
  client.receive_json({ "id": Json::number(second.id.to_double()), "value": [{ "station": "ws1/st1", "name": "Maple" }] })
  t.frame()
  assert_true(t.shown_of("Maple") is Some(_), msg="the reopened chat shows the current station")
  client.receive_json({ "id": Json::number(second.id.to_double()), "delta": [{ "path": [0, "name"], "set": "Pine" }] })
  t.frame()
  assert_true(t.shown_of("Pine") is Some(_), msg="the reopened chat follows later station updates")
  @ui.run_let_go()
  assert_true(client.peek_topic("stations", params~) is None)
}

///|
fn signal_client_source(client : @core.Client) -> Source {
  let base = @sfbase.made_source()
  {
    ..base,
    topic_read: fn(name, params) {
      let sub = client.follow_topic(name, params~)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, params) { client.follow_topic(name, params~).waiting },
    leave: fn(name, params) { client.leave_topic(name, params~) },
    release: fn(name, params) { client.release_topic(name, params~) },
    refresh: fn(name, params) { client.refresh_topic(name, params~) },
  }
}

///|
test "an untracked build read shares an existing graph reader without retaining the subscription" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let watcher = @signals.watch(fn() {  })
  watcher.read(fn() { src.topic("prefs", {}).get() |> ignore })
  @sfbase.held_build(1)
  @signals.untracked(fn() { src.topic("prefs", {}).get() |> ignore })
  @sfbase.held_end()
  watcher.stop()
  assert_true(client.peek_topic("prefs") is None, msg="the final graph reader releases the topic")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "refresh keeps existing signal and direct readers while replacing the wire request" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let direct = client.subscribe("filePeek")
  let live = src.topic("filePeek", {})
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(@sfbase.text(live.get().value, "text")) })
  client.receive_json({ "id": 1, "value": { "text": "before" } })
  (src.refresh)("filePeek", {})
  assert_eq(sent.length(), 3)
  assert_true(sent[1].contains("\"unsubscribe\":true"))
  assert_true(sent[2].contains("\"subscribe\""))
  assert_true(physical_equal(direct, client.peek_topic("filePeek").unwrap()))
  assert_eq(seen, ["", "before"], msg="refresh keeps the last value visible")
  client.receive_json({ "id": 1, "value": { "text": "late" } })
  client.receive_json({ "id": 2, "value": { "text": "after" } })
  assert_eq(seen, ["", "before", "after"])
  assert_eq(@sfbase.text(direct.value, "text"), "after")
  stop()
  assert_eq(sent.length(), 3, msg="the direct reader still owns the refreshed subscription")
  client.unsubscribe(direct)
  assert_eq(sent.length(), 4)
  assert_true(sent[3].contains("\"id\":2"))
}

///|
test "a direct subscriber can leave while a signal reader keeps the same topic" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let direct = client.subscribe("accounts")
  for _ in 0..<5 {
    assert_true(physical_equal(client.subscribe("accounts"), direct), msg="repeated frame reads share one direct hold")
  }
  let live = src.topic("accounts", {})
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(@sfbase.text(live.get().value, "name")) })
  client.receive_json({ "id": 1, "value": { "name": "before" } })
  client.unsubscribe(direct)
  assert_eq(sent.length(), 1, msg="a signal reader still holds the wire subscription")
  client.receive_json({ "id": 1, "value": { "name": "after" } })
  assert_eq(seen, ["", "before", "after"])
  stop()
  assert_eq(sent.length(), 2)
  assert_true(sent[1].contains("\"id\":1") && sent[1].contains("\"unsubscribe\":true"))
}

///|
test "a direct subscriber can leave while an untracked legacy reader still holds the topic" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let direct = client.subscribe("accounts")
  @sfbase.held_build(1)
  src.topic("accounts", {}).get().snapshot() |> ignore
  @sfbase.held_end()
  client.receive_json({ "id": 1, "value": { "name": "before" } })
  client.unsubscribe(direct)
  assert_eq(sent.length(), 1, msg="a legacy reader still holds the wire subscription")
  client.receive_json({ "id": 1, "value": { "name": "after" } })
  assert_eq(@sfbase.text(src.topic("accounts", {}).get().value, "name"), "after")
  @sfbase.held_build(2)
  @sfbase.held_end()
  (src.leave)("accounts", {})
  assert_eq(sent.length(), 2)
  assert_true(sent[1].contains("\"id\":1") && sent[1].contains("\"unsubscribe\":true"))
}

///|
test "the existing topic entry is a signal shared across immediate frames and released after the page leaves" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  @sfbase.held_build(10)
  let topic : @signals.Computed[@sfbase.TopicState] = src.topic("chat", {})
  assert_true(topic.get().value is None)
  assert_eq(sent.length(), 1)
  let sub = client.peek_topic("chat").unwrap()
  @sfbase.held_end()
  client.receive_json({ "id": 1, "value": { "title": "first" } })
  @sfbase.held_build(11)
  let again = src.topic("chat", {})
  assert_eq(@sfbase.text(again.get().value, "title"), "first")
  assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()), msg="page frames share the core subscription")
  assert_eq(sent.length(), 1, msg="the next frame does not resubscribe")
  @sfbase.held_end()
  @sfbase.held_build(12)
  @sfbase.held_end()
  (src.leave)("chat", {})
  assert_eq(sent.length(), 2)
  assert_true(sent[1].contains("\"unsubscribe\":true"))
}

///|
test "a core topic signal follows waiting, values, deltas, errors and recovery without a frame" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let live = src.topic("chat", { "session": "one" })
  let seen : Array[String] = []
  let stop = @signals.effect(fn() {
    let state = live.get()
    let what = if state.waiting {
      "waiting"
    } else if state.error is Some(_) {
      "error"
    } else {
      @sfbase.text(state.value, "title")
    }
    seen.push(what)
  })
  assert_eq(sent.length(), 1)
  assert_eq(seen, [""])
  client.receive_json({ "id": 1, "waiting": true })
  client.receive_json({ "id": 1, "value": { "title": "one", "other": 1 } })
  client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "two" }] })
  client.receive_json({ "id": 1, "error": { "message": "offline" } })
  client.receive_json({ "id": 1, "value": { "title": "back" } })
  assert_eq(seen, ["", "waiting", "one", "two", "error", "back"])
  stop()
  live.dispose()
}

///|
test "topic signals share the core subscription and release their graph independently" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let params : Map[String, Json] = { "session": "one" }
  let first = src.topic("chat", params)
  let second = src.topic("chat", params)
  let a : Array[String] = []
  let b : Array[String] = []
  let stop_a = @signals.effect(fn() { a.push(@sfbase.text(first.get().value, "title")) })
  let stop_b = @signals.effect(fn() { b.push(@sfbase.text(second.get().value, "title")) })
  assert_eq(sent.length(), 1)
  let sub = client.peek_topic("chat", params~).unwrap()
  client.receive_json({ "id": 1, "value": { "title": "one" } })
  stop_a()
  first.dispose()
  client.receive_json({ "id": 1, "value": { "title": "two" } })
  assert_eq(a, ["", "one"])
  assert_eq(b, ["", "one", "two"])
  stop_b()
  second.dispose()
  assert_false(sub.changes.watched())
  assert_eq(sent.length(), 2)
  assert_true(sent[1].contains("\"unsubscribe\":true"))
}

///|
test "a selected field follows the topic and ignores changes to another field" {
  let client = @core.Client::new(fn(_) {  })
  let src = signal_client_source(client)
  let live = src.topic("chat", {})
  let title = @signals.computed(fn(_) { @sfbase.text(live.get().value, "title") }, same=fn(a, b) { a == b })
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(title.get()) })
  client.receive_json({ "id": 1, "value": { "title": "one", "other": 1 } })
  client.receive_json({ "id": 1, "delta": [{ "path": ["other"], "set": 2 }] })
  client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "two" }] })
  assert_eq(seen, ["", "one", "two"])
  stop()
  title.dispose()
  live.dispose()
}

///|
test "a topic signal keeps following when a direct reader leaves the shared subscription" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let params : Map[String, Json] = { "session": "one" }
  let live = src.topic("chat", params)
  params["session"] = Json::string("another")
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(@sfbase.text(live.get().value, "title")) })
  assert_true(sent[0].contains("\"session\":\"one\""))
  let direct = client.subscribe("chat", params={ "session": "one" })
  client.receive_json({ "id": 1, "value": { "title": "one" } })
  client.unsubscribe(direct)
  assert_eq(sent.length(), 1)
  client.receive_json({ "id": 1, "value": { "title": "again" } })
  assert_eq(seen, ["", "one", "again"])
  stop()
  live.dispose()
}

///|
test "a topic signal still watched when the core client resets subscribes again" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let waits : Map[Int, String] = {}
  let ticket = Ref(0)
  client.track(fn(what) {
    ticket.val += 1
    waits[ticket.val] = what
    ticket.val
  }, fn(id) { waits.remove(id) })
  let src = signal_client_source(client)
  let live = src.topic("chat", {})
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(@sfbase.text(live.get().value, "title")) })
  let stale = client.peek_topic("chat").unwrap()
  client.receive_json({ "id": 1, "value": { "title": "before" } })
  client.call("prefs.set") |> ignore
  sent.clear()
  client.reset()
  assert_eq(sent.length(), 1, msg="a live reader must ask the new client for its topic")
  assert_eq(waits.length(), 1, msg="only the new subscription remains awaited")
  client.unsubscribe(stale)
  assert_eq(sent.length(), 1, msg="an old handle cannot end a new subscription with the same id")
  client.receive_json({ "id": 1, "value": { "title": "after" } })
  assert_eq(seen, ["", "before", "", "after"])
  assert_eq(waits.length(), 0)
  stop()
  live.dispose()
}

///|
test "an app reset keeps a topic shared by readers that are still alive" {
  @sfbase.reset()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let first = src.topic("chat", {})
  let seen : Array[String] = []
  let stop_first = @signals.effect(fn() { seen.push(@sfbase.text(first.get().value, "title")) })
  client.receive_json({ "id": 1, "value": { "title": "before" } })
  @sfbase.reset()
  let second = src.topic("chat", {})
  let stop_second = @signals.effect(fn() { second.get() |> ignore })
  assert_eq(sent.length(), 1, msg="a live reader still owns the original subscription")
  client.receive_json({ "id": 1, "value": { "title": "after" } })
  assert_eq(seen, ["", "before", "after"])
  stop_first()
  assert_eq(sent.length(), 1, msg="the second reader still owns it")
  stop_second()
  assert_eq(sent.length(), 2, msg="the last reader released it")
}

///|
test "a retained field follows the same core topic without a frame" {
  let client = @core.Client::new(fn(_) {  })
  let src = signal_client_source(client)
  let topic = src.topic("chat", {})
  let title = @signals.computed_scoped(fn(_) { @sfbase.text(topic.get().value, "title") }, same=fn(a, b) { a == b })
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(title.get()) })
  client.receive_json({ "id": 1, "value": { "title": "one" } })
  client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "two" }] })
  assert_eq(seen, ["", "one", "two"])
  stop()
}

///|
test "a topic is subscribed once until its last signal reader leaves" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let first = src.topic("chat", { "session": "shared" })
  let second = src.topic("chat", { "session": "shared" })
  let a : Array[String] = []
  let b : Array[String] = []
  let stop_a = @signals.effect(fn() { a.push(@sfbase.text(first.get().value, "title")) })
  let stop_b = @signals.effect(fn() { b.push(@sfbase.text(second.get().value, "title")) })
  client.receive_json({ "id": 1, "value": { "title": "one" } })
  client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "two" }] })
  assert_eq(sent.length(), 1, msg="topic changes must not end and recreate its subscription")
  stop_a()
  assert_eq(sent.length(), 1, msg="another reader still needs the topic")
  client.receive_json({ "id": 1, "value": { "title": "three" } })
  assert_eq(a, ["", "one", "two"])
  assert_eq(b, ["", "one", "two", "three"])
  stop_b()
  assert_eq(sent.length(), 2, msg="the last reader leaving ends the core subscription")
  assert_true(sent[1].contains("\"unsubscribe\":true"))
}

///|
test "a topic signal read once outside the graph does not keep a subscription" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let state = src.topic("chat", { "session": "once" })
  state.get() |> ignore
  let sub = client.subscribe("chat", params={ "session": "once" })
  assert_false(sub.changes.watched(), msg="an untracked read must not leave a signal graph behind")
  assert_true(sent.any(fn(s) { s.contains("\"unsubscribe\":true") }), msg="an untracked read must not keep the core subscribed")
}

///|
test "equivalent chat params, source wrappers and old readers release one shared core subscription" {
  for old_first in [true, false] {
    let sent : Array[String] = []
    let client = @core.Client::new(fn(s) { sent.push(s) })
    let base = @sfbase.made_source()
    let src : Source = {
      ..base,
      topic_read: fn(name, params) {
        let sub = client.follow_topic(name, params=@sfbase.core_topic_params(name, params))
        { value: sub.value, error: sub.error, version: sub.version }
      },
      waits: fn(name, params) { client.follow_topic(name, params=@sfbase.core_topic_params(name, params)).waiting },
      leave: fn(name, params) { client.leave_topic(name, params=@sfbase.core_topic_params(name, params)) },
      release: fn(name, params) { client.release_topic(name, params=@sfbase.core_topic_params(name, params)) },
    }
    let wrapped : Source = { ..src }
    let plain : Map[String, Json] = { "session": "same" }
    let compact : Map[String, Json] = { "session": "same", "compact": false }
    let legacy : Array[String] = []
    let modern : Array[String] = []
    let stop_old = @signals.effect(fn() { legacy.push(@sfbase.text(src.topic("chat", plain).get().value, "title")) })
    let first = src.topic("chat", compact)
    let second = wrapped.topic("chat", plain)
    let stop_a = @signals.effect(fn() { modern.push(@sfbase.text(first.get().value, "title")) })
    let stop_b = @signals.effect(fn() { second.get() |> ignore })
    client.receive_json({ "id": 1, "value": { "title": "before" } })
    wrapped.topic("chat", compact).get() |> ignore
    assert_eq(sent.length(), 1, msg="an untracked read must not interrupt an existing reader")
    if old_first { stop_old() } else { stop_a() }
    assert_eq(sent.length(), 1, msg="other readers still use the normalized core subscription")
    client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "after" }] })
    if old_first {
      assert_eq(modern, ["", "before", "after"])
      stop_a()
    } else {
      assert_eq(legacy, ["", "before", "after"])
      stop_old()
    }
    assert_eq(sent.length(), 1, msg="the other source wrapper is still following")
    stop_b()
    assert_eq(sent.length(), 2, msg="the final reader must release the core subscription")
    assert_true(sent[1].contains("\"unsubscribe\":true"))
  }
}

///|
test "an old untracked hold outlives a new signal reader and one-off read" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let params : Map[String, Json] = { "session": "old-holder" }
  @sfbase.held_build(1)
  @sfbase.hold(src, "core-signal-old-holder", "chat", params).get().snapshot() |> ignore
  @sfbase.held_end()
  client.receive_json({ "id": 1, "value": { "title": "kept" } })
  let live = src.topic("chat", params)
  live.get() |> ignore
  assert_eq(sent.length(), 1, msg="a one-off signal read cannot end the old hold")
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(@sfbase.text(live.get().value, "title")) })
  stop()
  assert_eq(sent.length(), 1, msg="leaving the new reader cannot end the old hold")
  client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "still kept" }] })
  assert_eq(@sfbase.text(@sfbase.hold(src, "core-signal-old-holder", "chat", params).get().value, "title"), "still kept")
  @sfbase.held_build(2)
  @sfbase.let_go(src, "core-signal-old-holder")
  assert_eq(sent.length(), 2)
  assert_true(sent[1].contains("\"unsubscribe\":true"))
}

///|
test "two old scopes and a signal reader independently hold one subscription" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let params : Map[String, Json] = { "session": "two-old" }
  @sfbase.held_build(20)
  @sfbase.hold(src, "first-old", "chat", params).get().snapshot() |> ignore
  @sfbase.hold(src, "second-old", "chat", params).get().snapshot() |> ignore
  let live = src.topic("chat", params)
  let stop = @signals.effect(fn() { live.get() |> ignore })
  client.receive_json({ "id": 1, "value": { "title": "before" } })
  @sfbase.held_build(21)
  @sfbase.let_go(src, "first-old")
  stop()
  assert_eq(sent.length(), 1, msg="the second old scope still holds the subscription")
  client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "after" }] })
  assert_eq(@sfbase.text(@sfbase.hold(src, "second-old", "chat", params).get().value, "title"), "after")
  @sfbase.held_build(22)
  @sfbase.let_go(src, "second-old")
  assert_eq(sent.length(), 2)
  assert_true(sent[1].contains("\"unsubscribe\":true"))
}

///|
test "two legacy scopes hand a subscription over within one frame" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let params : Map[String, Json] = { "session": "handover" }
  @sfbase.held_build(30)
  @sfbase.hold(src, "old-before", "chat", params).get().snapshot() |> ignore
  client.receive_json({ "id": 1, "value": { "title": "kept" } })
  @sfbase.let_go(src, "old-before")
  assert_eq(@sfbase.text(@sfbase.hold(src, "old-after", "chat", params).get().value, "title"), "kept")
  @sfbase.held_end()
  @sfbase.held_build(31)
  assert_eq(sent.length(), 1, msg="the handover must not end and recreate the topic")
  @sfbase.let_go(src, "old-after")
  assert_eq(sent.length(), 2)
}

///|
test "a legacy scope leaving in the final frame is released at that frame's end" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  @sfbase.held_build(40)
  @sfbase.hold(src, "last-frame", "chat", {}).get().snapshot() |> ignore
  @sfbase.let_go(src, "last-frame")
  assert_eq(sent.length(), 1)
  @sfbase.held_end()
  assert_eq(sent.length(), 2, msg="no next frame is needed to release the subscription")
}

///|
test "actual page-leave callbacks hand over and release a held topic in the same frame" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name != "held-check" { return base.topic(name, params).get().snapshot() }
      let sub = client.follow_topic(name, params~)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, params) {
      if name == "held-check" { client.follow_topic(name, params~).waiting } else { (base.waits)(name, params) }
    },
    release: fn(name, params) {
      if name == "held-check" { client.release_topic(name, params~) } else { (base.release)(name, params) }
    },
  }
  let first : ChatRef = { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }
  let second : ChatRef = { station: "ws1/st1", session: "s-c2", title: "", station_name: "" }
  let phase = Ref(0)
  let t = @ui.Tester::new(fn(c) {
    view(c, src)
    if phase.val == 0 {
      @sfbase.hold(src, @sfbase.chat_scope(first.station, first.session), "held-check", {}).get().snapshot() |> ignore
    } else if phase.val == 1 {
      @sfbase.hold(src, @sfbase.chat_scope(second.station, second.session), "held-check", {}).get().snapshot() |> ignore
    }
  }, w=390.0, h=844.0, platform=2)
  t.frame()
  client.receive_json({ "id": 1, "value": { "title": "kept" } })
  phase.val = 1
  left_pages.push(Chat(first))
  t.frame()
  assert_eq(sent.length(), 1, msg="the new page took the topic before pages-left released the old page")
  phase.val = 2
  left_pages.push(Chat(second))
  t.frame()
  assert_eq(sent.length(), 2, msg="pages-left must release it in the final frame")
  assert_true(sent[1].contains("\"unsubscribe\":true"))
}

///|
fn chat_signal_page_case(pop : Bool, intermediate : Bool) -> Unit raise {
  new_run()
  let sent : Array[String] = []
  let chat_lefts = Ref(0)
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture("chat")
  let chat : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let params = @sfbase.chat_params(chat)
  let which = fn(name : String, p : Map[String, Json]) {
    name == "prefs" || (name == "chat" && p.get("session") == Some(Json::string("s-c1")))
  }
  let src : Source = {
    ..base,
    topic_read: fn(name, p) {
      if !which(name, p) { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=@sfbase.core_topic_params(name, p))
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) {
      if which(name, p) { client.follow_topic(name, params=@sfbase.core_topic_params(name, p)).waiting } else { (base.waits)(name, p) }
    },
    leave: fn(name, p) {
      if name == "chat" && which(name, p) { chat_lefts.val += 1 }
      if which(name, p) { client.leave_topic(name, params=@sfbase.core_topic_params(name, p)) } else { (base.leave)(name, p) }
    },
    release: fn(name, p) {
      if which(name, p) { client.release_topic(name, params=@sfbase.core_topic_params(name, p)) } else { (base.release)(name, p) }
    },
  }
  open_chat(chat)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.frame()
  guard client.peek_topic("prefs") is Some(prefs_sub) else { fail("prefs subscription missing after first frame") }
  let prefs_value = match (base.topic_read)("prefs", {}).value {
    Some(Object(m)) => m.copy()
    _ => fail("prefs fixture is absent")
  }
  prefs_value["dropAs"] = "file"
  client.receive_json({ "id": Json::number(prefs_sub.id.to_double()), "value": Json::object(prefs_value) })
  t.frame()
  guard client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is Some(chat_sub) else {
    fail("chat subscription missing after opening: \{sent}")
  }
  let chat_value = match (base.topic_read)("chat", params).value {
    Some(Object(m)) => m.copy()
    _ => fail("chat fixture is absent")
  }
  chat_value["agents"] = [{ "session": { "key": "child-session" } }]
  client.receive_json({ "id": Json::number(chat_sub.id.to_double()), "value": Json::object(chat_value) })
  t.frame()
  guard t.shown_of("做完了：") is Some((x, y, w, h)) && w > 0.0 && h > 0.0 else { fail("the chat's message is outside the visible area") }
  assert_true(t.words().iter().any(fn(word) { word.0.contains("做完了：") && word.5 > 0.0 }), msg="the chat's message is transparent")
  let before_events = sent.length()
  @sfbase.machine_here.val = Some("ws1/st1")
  t.drop_files(x + w / 2.0, y + h / 2.0, [("报告.pdf", b"%PDF")], paths=["/Users/lin/报告.pdf"])
  t.frame()
  t.frame()
  let refs = @sfbase.writings.get(draft_key(chat)).map(fn(d) { d.files.get() }).unwrap_or([])
  assert_eq(refs.length(), 1)
  assert_eq(@sfbase.text(@sfbase.field(refs.get(0), "ref"), "mode"), "file")
  let link = @sfbase.link_target({ "opens": "item", "workspace": "ws1", "station": "st1", "session": "child-session", "service": "j-web" })
  assert_true(@sfbase.open_target(src, link, false, None))
  assert_true(app.nav.top() == Service("ws1/st1", "j-web"), msg="an agent's link stays over its chat")
  assert_eq(sent.length(), before_events, msg="event reads share the topics from the page")
  assert_true(app.nav.pages().iter().any(fn(p) { p is Chat(_) }))
  if pop {
    let start = t.time()
    home()
    assert_false(app.nav.pages().iter().any(fn(p) { p is Chat(_) }))
    t.frame()
    assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is Some(_), msg="the leaving page still has a reader")
    if intermediate { t.frame_at(start + 100.0) }
    // The same declared time with and without the intermediate frame must have the same owners.
    t.frame_at(start + 1000.0)
  } else {
    // The wide frame can replace its pane in place, with no transition.
    @sfbase.nav_over_home([])
    assert_false(app.nav.pages().iter().any(fn(p) { p is Chat(_) }))
    t.frame()
  }
  t.frame()
  assert_eq(chat_lefts.val, 1, msg="one chat leave was sent")
  assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is None, msg="leaving the page releases its chat")
  assert_true(physical_equal(prefs_sub, client.peek_topic("prefs").unwrap()), msg="the home page still reads prefs")
  @ui.run_let_go()
}

///|
test "a chat page's topic is shared with events and released when its pane is replaced" {
  chat_signal_page_case(false, false)
}

///|
test "a popped chat's last reader leaves at the same time with or without an intermediate frame" {
  chat_signal_page_case(true, false)
  chat_signal_page_case(true, true)
}

///|
test "a directly held accounts subscription survives source readers leaving and reset" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let direct = client.subscribe("accounts")
  let live = src.topic("accounts", {})
  let stop = @signals.effect(fn() { live.get() |> ignore })
  client.receive_json({ "id": 1, "value": { "signedIn": true } })
  stop()
  (src.leave)("accounts", {})
  assert_eq(sent.length(), 1, msg="leaving the Source must not close a directly held Sub")
  client.receive_json({ "id": 1, "delta": [{ "path": ["signedIn"], "set": false }] })
  assert_false(@sfbase.flag(direct.value, "signedIn"))
  client.reset()
  let after = client.subscribe("accounts")
  assert_false(physical_equal(after, direct))
  let again = src.topic("accounts", {})
  let stop_again = @signals.effect(fn() { again.get() |> ignore })
  client.receive_json({ "id": 1, "value": { "signedIn": true } })
  stop_again()
  (src.leave)("accounts", {})
  assert_true(@sfbase.flag(after.value, "signedIn"))
  assert_eq(sent.length(), 2, msg="the direct subscription after reset stays open")
  client.unsubscribe(after)
  assert_eq(sent.length(), 3)
}

///|
fn drive_place_row_case(intermediate : Bool) -> Unit raise {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture("drive")
  let params : Map[String, Json] = {
    "station": "ws1/st1", "root": Json::string(@sffixture.fix_docs), "path": "长篇小说.txt",
  }
  let ours = fn(name : String, p : Map[String, Json]) {
    name == "drivePlace" && @sfbase.text(Some(Json::object(p)), "path") == "长篇小说.txt"
  }
  let src : Source = {
    ..base,
    topic_read: fn(name, p) {
      if !ours(name, p) { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=p)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) { if ours(name, p) { client.follow_topic(name, params=p).waiting } else { (base.waits)(name, p) } },
    leave: fn(name, p) { if ours(name, p) { client.leave_topic(name, params=p) } else { (base.leave)(name, p) } },
    release: fn(name, p) { if ours(name, p) { client.release_topic(name, params=p) } else { (base.release)(name, p) } },
  }
  open_drive_fixture("drive")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.frame()
  guard client.peek_topic("drivePlace", params~) is Some(first) else { fail("the row did not subscribe: \{sent}") }
  assert_eq(sent.length(), 1, msg="the row subscribes once: \{sent}")
  let first_ask = try Some(@json.parse(sent[0])) catch { _ => None }
  assert_eq(@sfbase.text(@sfbase.field(first_ask, "subscribe"), "topic"), "drivePlace")
  assert_eq(@sfbase.number(first_ask, "id"), first.id.to_double())
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": { "at": 20, "of": 100 } })
  t.frame()
  guard t.shown_of("20%") is Some((_, _, w, h)) && w > 0.0 && h > 0.0 else { fail("the initial reading place is outside the visible area") }
  assert_true(t.words().iter().any(fn(word) { word.0.contains("20%") && word.5 > 0.0 }), msg="the initial reading place is transparent")
  let opened_at = t.time()
  t.tap_text("长篇小说.txt")
  if intermediate { t.frame_at(opened_at + 50.0) }
  t.frame_at(opened_at + 100.0)
  assert_true(physical_equal(first, client.peek_topic("drivePlace", params~).unwrap()), msg="the departing row still has its place")
  t.frame_at(opened_at + @ui.move_ms(390.0))
  t.frame()
  assert_true(client.peek_topic("drivePlace", params~) is None, msg="the covered list releases its reading place: \{sent}")
  assert_eq(sent.length(), 2, msg="the covered list unsubscribes once: \{sent}")
  let left = try Some(@json.parse(sent[1])) catch { _ => None }
  assert_true(@sfbase.flag(left, "unsubscribe"))
  assert_eq(@sfbase.number(left, "id"), first.id.to_double())
  let returned_at = t.time()
  t.back()
  if intermediate { t.frame_at(returned_at + 50.0) }
  t.frame_at(returned_at + @ui.move_ms(390.0))
  t.frame()
  guard client.peek_topic("drivePlace", params~) is Some(current) else { fail("returning did not read the place: \{sent}") }
  assert_true(current.id != first.id, msg="the returned row has a new subscription: \{sent}")
  assert_eq(sent.length(), 3, msg="the returned row subscribes once: \{sent}")
  let again = try Some(@json.parse(sent[2])) catch { _ => None }
  assert_eq(@sfbase.text(@sfbase.field(again, "subscribe"), "topic"), "drivePlace")
  assert_eq(@sfbase.number(again, "id"), current.id.to_double())
  client.receive_json({ "id": Json::number(current.id.to_double()), "value": { "at": 75, "of": 100 } })
  t.frame()
  guard t.shown_of("75%") is Some((_, _, w, h)) && w > 0.0 && h > 0.0 else { fail("the current reading place is outside the visible area") }
  assert_true(t.words().iter().any(fn(word) { word.0.contains("75%") && word.5 > 0.0 }), msg="the current reading place is transparent")
  client.receive_json({ "id": Json::number(current.id.to_double()), "delta": [{ "path": ["at"], "set": 80 }] })
  t.frame()
  guard t.shown_of("80%") is Some((_, _, w, h)) && w > 0.0 && h > 0.0 else { fail("the updated reading place is outside the visible area") }
  assert_true(t.words().iter().any(fn(word) { word.0.contains("80%") && word.5 > 0.0 }), msg="the updated reading place is transparent")
  @ui.run_let_go()
  assert_true(client.peek_topic("drivePlace", params~) is None, msg="ending the run releases the place")
  assert_eq(sent.length(), 4, msg="ending the run unsubscribes once: \{sent}")
  let last = try Some(@json.parse(sent[3])) catch { _ => None }
  assert_true(@sfbase.flag(last, "unsubscribe"))
  assert_eq(@sfbase.number(last, "id"), current.id.to_double())
}

///|
test "a drive row gets its current reading place after returning from the reader" {
  drive_place_row_case(false)
  drive_place_row_case(true)
}

///|
test "a chat after closing the switcher reads station changes made in the gap" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = @sffixture.fixture("home")
  let params : Map[String, Json] = { "scope": "ws1" }
  let src : Source = {
    ..base,
    topic_read: fn(name, p) {
      if name != "stations" { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=p)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) { if name == "stations" { client.follow_topic(name, params=p).waiting } else { (base.waits)(name, p) } },
    leave: fn(name, p) { if name == "stations" { client.leave_topic(name, params=p) } else { (base.leave)(name, p) } },
    release: fn(name, p) { if name == "stations" { client.release_topic(name, params=p) } else { (base.release)(name, p) } },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.frame()
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  guard client.peek_topic("stations", params~) is Some(first) else { fail("the switcher did not read stations: \{sent}") }
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": [{ "station": "ws1/st1", "name": "Cedar" }] })
  t.frame()
  t.key(@ui.key_escape)
  // The switcher closes immediately; inspect its first frame after Escape.
  t.frame()
  assert_true(client.peek_topic("stations", params~) is None, msg="the switcher's reader was not released before the chat's reader: \{sent}")
  // The server changes after unsubscribe. A late message from the old wire id must not become the new value.
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": [{ "station": "ws1/st1", "name": "Outdated" }] })
  open_chat_beside({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  t.frame()
  guard client.peek_topic("stations", params~) is Some(second) else { fail("the chat did not read stations: \{sent}") }
  assert_true(second.id != first.id, msg="the new reader must have its own wire id")
  assert_true(second.value is None, msg="the old value must not be reused before the current answer")
  assert_true(t.shown_of("Outdated") is None, msg="a late answer to the old subscription is not shown")
  assert_true(t.shown_of("Cedar") is None, msg="the old station value is not shown while the new subscription waits")
  client.receive_json({ "id": Json::number(second.id.to_double()), "value": [{ "station": "ws1/st1", "name": "Maple" }] })
  t.frame()
  assert_true(t.shown_of("Maple") is Some(_), msg="the chat shows the station's current value")
  client.receive_json({ "id": Json::number(second.id.to_double()), "delta": [{ "path": [0, "name"], "set": "Pine" }] })
  t.frame()
  assert_true(t.shown_of("Pine") is Some(_), msg="the chat follows later station updates")
  @ui.run_let_go()
}
