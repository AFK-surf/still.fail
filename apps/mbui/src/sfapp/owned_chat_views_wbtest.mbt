// The same chat can be visible in separate views. Exercise the actual chat derivation and client with separate owners.

///|
fn chat_title(src : Source, r : ChatRef) -> String {
  match view_of_chat(src, r).0 {
    Some(view) => view.title
    None => ""
  }
}

///|
test "two view sources share a chat and the remaining view follows its next value" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = chat_client_source(client)
  let first : Ref[Source?] = Ref(None)
  let second : Ref[Source?] = Ref(None)
  let first_tree = @view.Tree::new(fn(view) { first.val = Some(base.owned_by(view)) })
  let second_tree = @view.Tree::new(fn(view) { second.val = Some(base.owned_by(view)) })
  let r : ChatRef = { station: "ws1/st1", session: "s-owned-views", title: "", station_name: "" }
  let params = @sfbase.core_topic_params("chat", chat_params(r))
  let watch_first = @signals.watch(fn() {  })
  let watch_second = @signals.watch(fn() {  })
  let draw_first = Ref(true)
  let seen_first = Ref("")
  let seen_second = Ref("")
  let t = @ui.Tester::new(fn(_) {
    if draw_first.val {
      watch_first.read(fn() { seen_first.val = chat_title(first.val.unwrap(), r) })
    }
    watch_second.read(fn() { seen_second.val = chat_title(second.val.unwrap(), r) })
  })
  t.draw()
  let sub = client.peek_topic("chat", params~).unwrap()
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "title": "first value", "messages": [] } })
  t.draw()
  assert_eq(seen_first.val, "first value")
  assert_eq(seen_second.val, "first value")
  draw_first.val = false
  watch_first.stop()
  first_tree.dispose()
  assert_true(physical_equal(sub, client.peek_topic("chat", params~).unwrap()), msg="the second view keeps the same subscription")
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "title": "second value", "messages": [] } })
  t.draw()
  assert_eq(seen_second.val, "second value", msg="the surviving view sees updates after the other owner ends")
  watch_second.stop()
  second_tree.dispose()
  @sfbase.chat_inputs_left(r)
  assert_true(client.peek_topic("chat", params~) is None, msg="the last view releases the subscription")
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  let ended = sent.filter(fn(s) {
    let message = try Some(@json.parse(s)) catch { _ => None }
    @sfbase.flag(message, "unsubscribe") && @sfbase.number(message, "id") == sub.id.to_double()
  })
  assert_eq(ended.length(), 1)
  @ui.run_let_go()
}

///|
test "chat views with different projections do not share the first projection's value" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = chat_client_source(client)
  let projected = fn(title : String) -> Source {
    {
      ..base,
      topic_read: fn(name, params) {
        let topic = (base.topic_read)(name, params)
        if name == "chat" && topic.value is Some(_) {
          { ..topic, value: Some({ "title": Json::string(title), "messages": [] }) }
        } else {
          topic
        }
      },
    }
  }
  let first : Ref[Source?] = Ref(None)
  let second : Ref[Source?] = Ref(None)
  let first_tree = @view.Tree::new(fn(view) { first.val = Some(projected("first projection").owned_by(view)) })
  let second_tree = @view.Tree::new(fn(view) { second.val = Some(projected("second projection").owned_by(view)) })
  let r : ChatRef = { station: "ws1/st1", session: "s-owned-projections", title: "", station_name: "" }
  let params = @sfbase.core_topic_params("chat", chat_params(r))
  let watch_first = @signals.watch(fn() {  })
  let watch_second = @signals.watch(fn() {  })
  let seen_first = Ref("")
  let seen_second = Ref("")
  let t = @ui.Tester::new(fn(_) {
    watch_first.read(fn() { seen_first.val = chat_title(first.val.unwrap(), r) })
    watch_second.read(fn() { seen_second.val = chat_title(second.val.unwrap(), r) })
  })
  t.draw()
  let sub = client.peek_topic("chat", params~).unwrap()
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "title": "wire value", "messages": [] } })
  t.draw()
  assert_eq(seen_first.val, "first projection")
  assert_eq(seen_second.val, "second projection")
  watch_first.stop()
  watch_second.stop()
  first_tree.dispose()
  second_tree.dispose()
  @sfbase.chat_inputs_left(r)
  assert_true(client.peek_topic("chat", params~) is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  let ended = sent.filter(fn(s) {
    let message = try Some(@json.parse(s)) catch { _ => None }
    @sfbase.flag(message, "unsubscribe") && @sfbase.number(message, "id") == sub.id.to_double()
  })
  assert_eq(ended.length(), 1)
  @ui.run_let_go()
}

///|
fn chat_left_projection_case(reverse : Bool, second_has_value : Bool) -> Unit raise {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let calls : Array[(String, Json)] = []
  let source = chat_client_source(client)
  let base : Source = {
    ..source,
    call: fn(name, params, done) {
      calls.push((name, params))
      done(Ok(Json::null()))
    },
  }
  let projected = fn(thread : Double, has_value : Bool) -> Source {
    {
      ..base,
      topic_read: fn(name, params) {
        let topic = (base.topic_read)(name, params)
        if name == "chat" && topic.value is Some(_) {
          { ..topic, value: if has_value {
            Some({ "thread": { "id": Json::number(thread) }, "title": Json::string(@sfbase.text(topic.value, "title")), "messages": [] })
          } else { None } }
        } else {
          topic
        }
      },
    }
  }
  let first : Ref[Source?] = Ref(None)
  let second : Ref[Source?] = Ref(None)
  let first_tree = @view.Tree::new(fn(view) { first.val = Some(projected(101.0, true).owned_by(view)) })
  let second_tree = @view.Tree::new(fn(view) { second.val = Some(projected(202.0, second_has_value).owned_by(view)) })
  let r : ChatRef = { station: "ws1/st1", session: "s-owned-leave", title: "", station_name: "" }
  let params = @sfbase.core_topic_params("chat", chat_params(r))
  let watch_first = @signals.watch(fn() {  })
  let marked_second = Ref(0)
  let watch_second = @signals.watch(fn() { marked_second.val += 1 })
  let seen_second = Ref("")
  let draw_first = Ref(true)
  let t = @ui.Tester::new(fn(_) {
    let a = fn() { if draw_first.val { watch_first.read(fn() { view_of_chat(first.val.unwrap(), r) |> ignore }) } }
    let b = fn() { watch_second.read(fn() { seen_second.val = chat_title(second.val.unwrap(), r) }) }
    if reverse { b(); a() } else { a(); b() }
  })
  t.draw()
  let sub = client.peek_topic("chat", params~).unwrap()
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "title": "before", "messages": [] } })
  t.draw()
  let rd = @sfbase.reading_of(r.station + "\u{1}" + r.session)
  rd.placed = true
  let before = sent.length()
  chat_left(first.val.unwrap(), r)
  let focus = calls.filter(fn(call) { call.0 == "client.focus" })
  let place = calls.filter(fn(call) { call.0 == "chat.place" })
  assert_eq(focus.length(), 1)
  assert_eq(@sfbase.number(@sfbase.field(Some(focus[0].1), "left"), "thread"), 101.0, msg="leaving tells the first source's thread")
  assert_eq(place.length(), 1)
  assert_eq(@sfbase.number(Some(place[0].1), "thread"), 101.0, msg="the place belongs to the first source's thread")
  assert_eq(sent.length(), before, msg="checking the kept view does not subscribe or leave another reader")
  draw_first.val = false
  watch_first.stop()
  first_tree.dispose()
  assert_true(physical_equal(sub, client.peek_topic("chat", params~).unwrap()))
  let already_stale = watch_second.is_stale()
  let marked_before = marked_second.val
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "title": "after", "messages": [] } })
  assert_true(already_stale || marked_second.val > marked_before, msg="the other view is stale before another frame")
  t.draw()
  if second_has_value { assert_eq(seen_second.val, "after", msg="the other view reads the new value") }
  assert_true(physical_equal(sub, client.peek_topic("chat", params~).unwrap()))
  watch_second.stop()
  second_tree.dispose()
  @sfbase.chat_inputs_left(r)
  assert_true(client.peek_topic("chat", params~) is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  let ended = sent.filter(fn(s) {
    let message = try Some(@json.parse(s)) catch { _ => None }
    @sfbase.flag(message, "unsubscribe") && @sfbase.number(message, "id") == sub.id.to_double()
  })
  assert_eq(ended.length(), 1)
  @ui.run_let_go()
}

///|
test "leaving the first projected chat uses its thread when the second was read last" {
  chat_left_projection_case(false, true)
}

///|
test "leaving the first projected chat uses its thread when it was read last" {
  chat_left_projection_case(true, true)
}

///|
test "leaving a projected chat keeps its thread when another source has no value" {
  chat_left_projection_case(false, false)
}
