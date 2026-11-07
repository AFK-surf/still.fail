// Exercise the real application tree and row; no page source is created by this fixture.

///|
fn actual_row_handoff(legacy : Bool, end_early : Bool, intermediate : Bool, duplicate : Bool, changed_place? : Bool = false) -> Unit raise {
  new_run()
  let sent : Array[String] = []
  let left : Array[Map[String, Json]] = []
  let calls : Array[(String, Json)] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture("chat")
  let chat : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let raw = chat_params(chat)
  let params = @sfbase.core_topic_params("chat", raw)
  let which = fn(name : String, p : Map[String, Json]) {
    name == "chat" && p.get("station") == Some(Json::string(chat.station)) && p.get("session") == Some(Json::string(chat.session))
  }
  let src : Source = {
    ..base,
    call: fn(name, args, done) { calls.push((name, args)); (base.call)(name, args, done) },
    topic_key: fn(name, p) { @sfbase.wire_topic_key(name, @sfbase.core_topic_params(name, p)) },
    topic_read: fn(name, p) {
      if !which(name, p) { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=@sfbase.core_topic_params(name, p))
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) {
      if which(name, p) { client.follow_topic(name, params=@sfbase.core_topic_params(name, p)).waiting } else { (base.waits)(name, p) }
    },
    leave: fn(name, p, reason) {
      if which(name, p) { left.push(p.copy()) }
      if reason is @sfbase.TopicLeave::Owned(stop) { stop(); return }
      if which(name, p) { client.leave_topic(name, params=@sfbase.core_topic_params(name, p)) } else { (base.leave)(name, p, reason) }
    },
    release: fn(name, p) {
      if which(name, p) { client.release_topic(name, params=@sfbase.core_topic_params(name, p)) } else { (base.release)(name, p) }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2, pointing=Finger, native=Finger)
  t.run_for(first_page_ms + @ui.move_most_ms)
  let old = if legacy { Some(@signals.untracked(fn() { client.follow_topic("chat", params~) })) } else { None }
  let (x, y) = t.find(chat.title).unwrap()
  t.press_at(x, y)
  guard client.peek_topic("chat", params~) is Some(original) else { fail("the actual row did not prefetch") }
  if old is Some(earlier) { assert_true(physical_equal(earlier, original)) }
  let value = (base.topic_read)("chat", raw).value.unwrap()
  client.receive_json({ "id": Json::number(original.id.to_double()), "value": value })
  t.touch(2, x, y)
  let (serial, _) = app.nav.top_stay()
  assert_true(@sfbase.chat_open_is_pending(serial), msg="the row's reader is pending before the page is built")
  assert_true(client.peek_topic("chat", params~) is Some(s) && physical_equal(s, original), msg="the prefetch survives the up event before a frame")
  if end_early {
    @ui.run_let_go()
  } else {
    t.draw()
    assert_true(app.nav.top() is Chat(_), msg="the actual row opened the chat")
    t.run_for(first_page_ms + @ui.move_most_ms)
    assert_false(@sfbase.chat_open_is_pending(serial), msg="the page acquired its reader and released the pending handover")
    assert_true(client.peek_topic("chat", params~) is Some(s) && physical_equal(s, original), msg="the actual page took the original subscription")
    assert_eq(lease_ended(sent, original.id), 0, msg="handover did not unsubscribe")
    let updated = match value {
      Object(fields) => fields.copy()
      _ => fail("the chat fixture is not an object")
    }
    updated["title"] = "handoff update"
    updated["thread"] = { "id": 101.0 }
    client.receive_json({ "id": Json::number(original.id.to_double()), "value": Json::object(updated) })
    t.frame()
    guard t.shown_of("handoff update") is Some((x, y, w, h)) && w > 0.0 && h > 0.0 && x < t.w && y < t.h && x + w > 0.0 && y + h > 0.0 else {
      fail("the page's later update is outside its visible clipped area")
    }
    assert_true(t.words().iter().any(fn(word) { word.0.contains("handoff update") && word.5 > 0.0 }), msg="the page's later update is not transparent")
    if duplicate {
      let reading = @sfbase.reading_of(chat.station + "\u{1}" + chat.session)
      reading.placed = true
      // This equal entry is removed before it has had a frame or its own page source.
      app.nav.push(Chat(chat))
    }
    let earlier_focus = calls.filter(fn(call) { call.0 == "client.focus" && @sfbase.field(Some(call.1), "left") is Some(_) }).length()
    let earlier_place = calls.filter(fn(call) { call.0 == "chat.place" }).length()
    let start = t.time()
    home()
    assert_true(app.nav.moving(), msg="the narrow chat is sliding away")
    t.frame()
    assert_true(client.peek_topic("chat", params~) is Some(s) && physical_equal(s, original), msg="the sliding chat still reads the original subscription")
    assert_eq(lease_ended(sent, original.id), 0)
    if intermediate {
      t.frame_at(start + 100.0)
      assert_true(app.nav.moving(), msg="the narrow page is still sliding at the intermediate frame")
      assert_true(client.peek_topic("chat", params~) is Some(s) && physical_equal(s, original), msg="the intermediate frame keeps the original subscription")
      assert_eq(lease_ended(sent, original.id), 0)
    }
    if duplicate && changed_place {
      // The location remembered by the core differs from the page's current location, so leaving has to tell it.
      @sfbase.reading_of(chat.station + "\u{1}" + chat.session).told_place = "older place"
    }
    t.frame_at(start + 1000.0)
    t.frame()
    if duplicate {
      let focus = calls.filter(fn(call) { call.0 == "client.focus" && @sfbase.field(Some(call.1), "left") is Some(_) })
      assert_eq(focus.length(), earlier_focus + 1, msg="the rendered page still reports its departure")
      assert_eq(@sfbase.number(@sfbase.field(Some(focus[focus.length() - 1].1), "left"), "thread"), 101.0)
      let place = calls.filter(fn(call) { call.0 == "chat.place" })
      assert_true(earlier_place > 0, msg="the rendered page already reported its reading place")
      let expected_places = if changed_place { earlier_place + 1 } else { earlier_place }
      assert_eq(place.length(), expected_places, msg="leaving reports a changed place and does not repeat an unchanged one")
      assert_eq(@sfbase.number(Some(place[place.length() - 1].1), "thread"), 101.0)
    } else {
      assert_eq(left.length(), 1, msg="the chat page sent one leave callback")
    }
  }
  if old is Some(earlier) {
    guard client.peek_topic("chat", params~) is Some(still) else { fail("the independent legacy reader was released") }
    assert_true(physical_equal(earlier, still))
    client.receive_json({ "id": Json::number(earlier.id.to_double()), "value": { "title": "legacy update", "messages": [] } })
    assert_eq(@sfbase.text(earlier.value, "title"), "legacy update")
    client.leave_topic("chat", params~)
  }
  assert_true(client.peek_topic("chat", params~) is None, msg="the last reader released the chat")
  let subscribes = sent.filter(fn(s) {
    let msg = try Some(@json.parse(s)) catch { _ => None }
    let sub = @sfbase.field(msg, "subscribe")
    @sfbase.text(sub, "topic") == "chat" && @sfbase.text(sub, "station") == chat.station && @sfbase.text(sub, "session") == chat.session
  })
  assert_eq(subscribes.length(), 1, msg="the target chat did not subscribe again during handover")
  assert_eq(lease_ended(sent, original.id), 1, msg="the original subscription ended once")
  @ui.run_let_go()
}

///|
test "actual row hands a quick press to its page without an intermediate frame" {
  actual_row_handoff(false, false, false, false)
}

///|
test "actual row handover preserves an independent legacy reader" {
  actual_row_handoff(true, false, false, false)
}

///|
test "ending the host during row handover releases the pending reader" {
  actual_row_handoff(false, true, false, false)
}

///|
test "an actual row's page releases after the same pop with an intermediate frame" {
  actual_row_handoff(false, false, true, false)
}

///|
test "an undrawn equal chat entry does not steal the visible page's leave" {
  actual_row_handoff(false, false, false, true)
}

///|
test "an undrawn equal chat entry preserves the independent legacy reader" {
  actual_row_handoff(true, false, false, true)
}

///|
test "an undrawn equal chat entry does not hide a changed place at leave" {
  actual_row_handoff(false, false, false, true, changed_place=true)
}

///|
test "a changed place at leave keeps an independent legacy reader" {
  actual_row_handoff(true, false, false, true, changed_place=true)
}
