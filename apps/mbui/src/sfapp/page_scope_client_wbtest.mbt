// Exercise the actual page Source with an in-memory Client.

///|
fn page_diag_chat_page_case(pop : Bool, intermediate : Bool, legacy : Bool, cover : Bool) -> Unit raise {
  new_run()
  let sent : Array[String] = []
  let calls : Array[(String, Json)] = []
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
    call: fn(name, args, done) {
      calls.push((name, args))
      (base.call)(name, args, done)
    },
    topic_read: fn(name, p) {
      if !which(name, p) { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=@sfbase.core_topic_params(name, p))
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) {
      if which(name, p) { client.follow_topic(name, params=@sfbase.core_topic_params(name, p)).waiting } else { (base.waits)(name, p) }
    },
    leave: fn(name, p, reason) {
      if name == "chat" && which(name, p) { chat_lefts.val += 1 }
      if reason is @sfbase.TopicLeave::Owned(stop) { stop(); return }
      if which(name, p) { client.leave_topic(name, params=@sfbase.core_topic_params(name, p)) } else { (base.leave)(name, p, reason) }
    },
    release: fn(name, p) {
      if which(name, p) { client.release_topic(name, params=@sfbase.core_topic_params(name, p)) } else { (base.release)(name, p) }
    },
  }
  let old_reader = if legacy {
    Some(@signals.untracked(fn() { client.follow_topic("chat", params=@sfbase.core_topic_params("chat", params)) }))
  } else { None }
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
    fail("chat subscription missing after opening: \{Repr(sent)}")
  }
  if old_reader is Some(old) {
    assert_true(physical_equal(old, chat_sub), msg="the page shares the legacy reader's original subscription")
  }
  let chat_value = match (base.topic_read)("chat", params).value {
    Some(Object(m)) => m.copy()
    _ => fail("chat fixture is absent")
  }
  chat_value["agents"] = [{ "session": { "key": "child-session" } }]
  chat_value["thread"] = { "id": 101.0 }
  client.receive_json({ "id": Json::number(chat_sub.id.to_double()), "value": Json::object(chat_value) })
  t.frame()
  let reading = @sfbase.reading_of(chat.station + "\u{1}" + chat.session)
  reading.placed = true
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
  if cover {
    // (a page over the chat: another chat, by a chat's link, over it on 大屏 as a link in a message opens it,
    // Nav::push_over; popped or replaced before a frame builds it)
    let link = @sfbase.link_target({ "opens": "chat", "workspace": "ws1", "station": "st1", "chat": "s-c2" })
    assert_true(@sfbase.open_target(src, link, false, None))
    assert_true(app.nav.top() == Chat(@sfbase.chat_ref("ws1/st1", "s-c2")), msg="another chat's link opens it over the chat")
  }
  assert_eq(sent.length(), before_events, msg="event reads share the topics from the page")
  assert_true(app.nav.pages().iter().any(fn(p) { p is Chat(_) }))
  if pop {
    let start = t.time()
    home()
    assert_false(app.nav.pages().iter().any(fn(p) { p is Chat(_) }))
    assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is Some(s) && physical_equal(s, chat_sub), msg="the last rendered page still has its original subscription")
    t.frame()
    assert_false(app.nav.moving())
    assert_true(t.shown_of("做完了：") is None)
    assert_eq(chat_lefts.val, 1)
    if legacy {
      assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is Some(s) && physical_equal(s, chat_sub), msg="the independent reader still holds the original subscription")
    } else {
      assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is None, msg="the last reader left with the page")
    }
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
  // The callback remains observable when the page releases its own reader.
  assert_eq(chat_lefts.val, 1)
  let focus = calls.filter(fn(call) { call.0 == "client.focus" && @sfbase.field(Some(call.1), "left") is Some(_) })
  assert_eq(focus.length(), 1, msg="the actual page tells the core which chat was left")
  assert_eq(@sfbase.number(@sfbase.field(Some(focus[0].1), "left"), "thread"), 101.0, msg="the leave uses the page's thread")
  let place = calls.filter(fn(call) { call.0 == "chat.place" })
  assert_eq(place.length(), 1, msg="the actual page reports its reading place")
  assert_eq(@sfbase.number(Some(place[0].1), "thread"), 101.0, msg="the place uses the page's thread")
  if legacy {
    guard old_reader is Some(old) else { fail("the test did not establish the legacy reader") }
    guard client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is Some(still) else {
      fail("the independent legacy reader no longer has a subscription after the page left")
    }
    assert_true(physical_equal(old, still), msg="the independent legacy reader still has its original subscription")
    let updated = chat_value.copy()
    updated["title"] = "after page left"
    client.receive_json({ "id": Json::number(old.id.to_double()), "value": Json::object(updated) })
    assert_eq(@sfbase.text(old.value, "title"), "after page left", msg="the surviving legacy reader receives the next value")
    client.leave_topic("chat", params=@sfbase.core_topic_params("chat", params))
  }
  assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is None, msg="the last actual owner released the chat")
  let same_id = sent.filter(fn(s) {
    let message = try Some(@json.parse(s)) catch { _ => None }
    @sfbase.number(message, "id") == chat_sub.id.to_double()
  })
  assert_eq(same_id.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(same_id.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
  let chat_subscribes = sent.filter(fn(s) {
    let message = try Some(@json.parse(s)) catch { _ => None }
    let sub = @sfbase.field(message, "subscribe")
    @sfbase.text(sub, "topic") == "chat" && @sfbase.text(sub, "station") == chat.station && @sfbase.text(sub, "session") == chat.session
  })
  assert_eq(chat_subscribes.length(), 1, msg="the target chat did not subscribe with a second ID")
  guard client.peek_topic("prefs") is Some(prefs_now) else { fail("home lost the prefs subscription") }
  assert_true(physical_equal(prefs_sub, prefs_now), msg="the home page still reads prefs")
  @ui.run_let_go()
}

///|
test "actual page source releases a replaced chat with no other owner" {
  page_diag_chat_page_case(false, false, false, true)
}

///|
test "actual page source releases a popped chat without an intermediate frame" {
  page_diag_chat_page_case(true, false, false, true)
}

///|
test "actual page source preserves an independent legacy chat reader" {
  page_diag_chat_page_case(false, false, true, true)
}

///|
test "an actual top chat releases on the first frame of its pop" {
  page_diag_chat_page_case(true, false, false, false)
}

///|
test "an actual top chat stays released at the intermediate pop frame" {
  page_diag_chat_page_case(true, true, false, false)
}
