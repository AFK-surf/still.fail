///|
fn independent_wide_pop_case(pop : Bool, intermediate : Bool, legacy : Bool, cover : Bool, other_kind? : Int = 0, render_cover? : Bool = false) -> Unit raise {
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
  let other_state = src.topic("chat", params)
  let other_watch = if other_kind == 2 {
    let watch = @signals.watch(fn() {  })
    watch.read(fn() { other_state.get() }) |> ignore
    Some(watch)
  } else { None }
  let old_reader = if other_kind == 1 {
    Some(client.subscribe("chat", params=@sfbase.core_topic_params("chat", params)))
  } else if other_kind == 2 {
    client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params))
  } else if legacy {
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
  if cover && !render_cover {
    // (a page over the chat: another chat, by a chat's link, over it on 大屏 as a link in a message opens it,
    // Nav::push_over; popped before a frame builds it)
    let link = @sfbase.link_target({ "opens": "chat", "workspace": "ws1", "station": "st1", "chat": "s-c2" })
    assert_true(@sfbase.open_target(src, link, false, None))
    assert_true(app.nav.top() == Chat(@sfbase.chat_ref("ws1/st1", "s-c2")), msg="another chat's link opens it over the chat")
  }
  if render_cover {
    // (an agent's web service asked as a page from its chat: on 大屏 handed over to the chat's side panel as it comes
    // on top, sfdesk's beside_follow, before any frame: the chat on top again, the service's tab asked in front of the
    // core, at once)
    let link = @sfbase.link_target({ "opens": "item", "workspace": "ws1", "station": "st1", "session": "child-session", "service": "j-web" })
    let asked = calls.length()
    assert_true(@sfbase.open_target(src, link, false, None))
    assert_true(app.nav.top() is Chat(c) && c.station == chat.station && c.session == chat.session, msg="an agent's service is handed over to its chat at once")
    let opened = Ref(0)
    for k = asked; k < calls.length(); k = k + 1 {
      if calls[k].0 == "chat.tabs.open" && @sfbase.text(Some(calls[k].1), "tab") == "service:j-web" { opened.val += 1 }
    }
    assert_eq(opened.val, 1, msg="the service's tab asked in front beside its chat at once")
    // The Client is isolated from the fixture's core: give it the tab update a real core would publish.
    t.frame()
    t.frame()
    let with_tabs = chat_value.copy()
    with_tabs["tabs"] = { "open": ["service:j-web"], "shown": "service:j-web", "auto": true }
    client.receive_json({ "id": Json::number(chat_sub.id.to_double()), "value": Json::object(with_tabs) })
    t.run_for(@ui.move_most_ms)
    assert_true(service_pages.contains(service_key("ws1/st1", "j-web")), msg="the service page was actually built")
    assert_true(t.query(Button, label="刷新") is Some(_), msg="the service page's controls are present")
    assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is Some(s) && physical_equal(s, chat_sub), msg="the underlying chat keeps its reader while the service is built")
  }
  assert_eq(sent.length(), before_events, msg="event reads share the topics from the page")
  assert_true(app.nav.pages().iter().any(fn(p) { p is Chat(_) }))
  let focus_before = calls.filter(fn(call) { call.0 == "client.focus" && @sfbase.field(Some(call.1), "left") is Some(_) }).length()
  if pop {
    let start = t.time()
    home()
    assert_false(app.nav.pages().iter().any(fn(p) { p is Chat(_) }))
    assert_false(app.nav.moving(), msg="the wide navigation is not animating")
    if !render_cover { assert_true(t.shown_of("做完了：") is Some(_), msg="the last rendered chat is visible before the next frame") }
    assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is Some(s) && physical_equal(s, chat_sub), msg="the original subscription remains before that frame")
    assert_eq(lease_ended(sent, chat_sub.id), 0)
    t.frame()
    assert_true(t.shown_of("做完了：") is None, msg="the chat is no longer visible after the frame")
    assert_false(app.nav.moving())
    assert_eq(chat_lefts.val, 1, msg="the page has sent its leave")
    if legacy {
      assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is Some(s) && physical_equal(s, chat_sub), msg="the independent reader still owns the original subscription")
      assert_eq(lease_ended(sent, chat_sub.id), 0)
    } else {
      assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is None, msg="the page's last reader has left")
      assert_eq(lease_ended(sent, chat_sub.id), 1)
    }
    if intermediate {
      t.frame_at(start + 100.0)
      assert_false(app.nav.moving())
      assert_true(t.shown_of("做完了：") is None)
      if legacy {
        assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is Some(s) && physical_equal(s, chat_sub))
        assert_eq(lease_ended(sent, chat_sub.id), 0)
      } else {
        assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is None)
        assert_eq(lease_ended(sent, chat_sub.id), 1)
      }
    }
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
  assert_eq(focus.length(), focus_before + 1, msg="the actual page tells the core which chat was left")
  assert_eq(@sfbase.number(@sfbase.field(Some(focus[focus.length() - 1].1), "left"), "thread"), 101.0, msg="the leave uses the page's thread")
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
    if other_kind == 1 {
      client.unsubscribe_topic("chat", params=@sfbase.core_topic_params("chat", params))
    } else if other_kind == 2 {
      assert_eq(@sfbase.text(other_state.get().value, "title"), "after page left", msg="the independent graph receives the update")
      other_watch.unwrap().stop()
    } else {
      client.leave_topic("chat", params=@sfbase.core_topic_params("chat", params))
    }
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
test "wide pop cover false, legacy false, intermediate false" {
  independent_wide_pop_case(true, false, false, false)
}

///|
test "wide pop cover false, legacy false, intermediate true" {
  independent_wide_pop_case(true, true, false, false)
}

///|
test "wide pop cover false, legacy true, intermediate false" {
  independent_wide_pop_case(true, false, true, false)
}

///|
test "wide pop cover false, legacy true, intermediate true" {
  independent_wide_pop_case(true, true, true, false)
}

///|
test "wide pop cover false, other kind 1, intermediate false" {
  independent_wide_pop_case(true, false, true, false, other_kind=1)
}

///|
test "wide pop cover false, other kind 1, intermediate true" {
  independent_wide_pop_case(true, true, true, false, other_kind=1)
}

///|
test "wide pop cover false, other kind 2, intermediate false" {
  independent_wide_pop_case(true, false, true, false, other_kind=2)
}

///|
test "wide pop cover false, other kind 2, intermediate true" {
  independent_wide_pop_case(true, true, true, false, other_kind=2)
}

///|
test "wide pop cover true, legacy false, intermediate false" {
  independent_wide_pop_case(true, false, false, true)
}

///|
test "wide pop cover true, legacy false, intermediate true" {
  independent_wide_pop_case(true, true, false, true)
}

///|
test "wide pop cover true, legacy true, intermediate false" {
  independent_wide_pop_case(true, false, true, true)
}

///|
test "wide pop cover true, legacy true, intermediate true" {
  independent_wide_pop_case(true, true, true, true)
}

///|
test "wide pop cover true, other kind 1, intermediate false" {
  independent_wide_pop_case(true, false, true, true, other_kind=1)
}

///|
test "wide pop cover true, other kind 1, intermediate true" {
  independent_wide_pop_case(true, true, true, true, other_kind=1)
}

///|
test "wide pop cover true, other kind 2, intermediate false" {
  independent_wide_pop_case(true, false, true, true, other_kind=2)
}

///|
test "wide pop cover true, other kind 2, intermediate true" {
  independent_wide_pop_case(true, true, true, true, other_kind=2)
}

///|
test "wide pop after service is built, other kind 0, intermediate false" {
  independent_wide_pop_case(true, false, false, true, other_kind=0, render_cover=true)
}

///|
test "wide pop after service is built, other kind 0, intermediate true" {
  independent_wide_pop_case(true, true, false, true, other_kind=0, render_cover=true)
}

///|
test "wide pop after service is built, other kind 1, intermediate false" {
  independent_wide_pop_case(true, false, true, true, other_kind=1, render_cover=true)
}

///|
test "wide pop after service is built, other kind 1, intermediate true" {
  independent_wide_pop_case(true, true, true, true, other_kind=1, render_cover=true)
}

///|
test "wide pop after service is built, other kind 2, intermediate false" {
  independent_wide_pop_case(true, false, true, true, other_kind=2, render_cover=true)
}

///|
test "wide pop after service is built, other kind 2, intermediate true" {
  independent_wide_pop_case(true, true, true, true, other_kind=2, render_cover=true)
}
