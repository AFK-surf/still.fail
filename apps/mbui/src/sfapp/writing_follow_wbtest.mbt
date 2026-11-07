// A draft follows its core topic for its lifetime, including when no page is being built.

///|
test "draft changes reach its readers without another page build" {
  new_run()
  let initial : Json = {
    "version": 1,
    "rev": 1,
    "text": "first",
    "files": [],
    "quotes": [],
  }
  let topic : @signals.Signal[@sfbase.Topic] = @signals.signal({
    value: Some(initial), error: None, version: 1,
  })
  let base = @sfbase.made_source()
  let src : @sfbase.Source = {
    ..base,
    topic: fn(name, params) {
      if name == "composer" { topic.get() } else { (base.topic)(name, params) }
    },
  }
  let held : Ref[@sfbase.Writing?] = Ref(None)
  let stop = @signals.effect_scope(fn() {
    held.val = Some(@sfbase.writing(src, "station:chat"))
  })
  let w = held.val.unwrap()
  let marked = Ref(0)
  let watch = @signals.watch(fn() { marked.val += 1 })
  watch.read(fn() { (w.text.get(), @sfbase.writing_files(w).length()) }) |> ignore
  let next : Json = {
    "version": 2,
    "rev": 2,
    "text": "second",
    "files": [{ "id": "f1", "name": "file.txt" }],
    "quotes": [],
  }
  topic.set({ value: Some(next), error: None, version: 2 })
  assert_eq(w.text.get(), "second")
  assert_eq(w.field.text(), "second")
  assert_eq(@sfbase.writing_files(w).length(), 1)
  assert_true(marked.val > 0)
  watch.stop()
  stop()
  assert_false(topic.watched(), msg="a closed page must release its draft subscription")
  @sfbase.writings_reset()
}

///|
test "a retained node reads the same draft without being made again" {
  new_run()
  let topic : @signals.Signal[@sfbase.Topic] = @signals.signal({
    value: Some({ "version": 1, "rev": 1, "text": "first" }), error: None, version: 1,
  })
  let base = @sfbase.made_source()
  let src : @sfbase.Source = { ..base, topic: fn(_, _) { topic.get() } }
  let made = Ref(0)
  let id : Ref[@view.NodeId?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(node) {
      made.val += 1
      id.val = Some(node.id())
      let w = @sfbase.writing(src, "station:chat")
      node.words(By(fn() { w.text.get() })) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(tree.drawn_of(id.val.unwrap()).unwrap().words, "first")
  topic.set({ value: Some({ "version": 2, "rev": 2, "text": "second" }), error: None, version: 2 })
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(tree.drawn_of(id.val.unwrap()).unwrap().words, "second")
  assert_eq(made.val, 1)
  tree.dispose()
  assert_false(topic.watched())
  @sfbase.writings_reset()
}

///|
test "a shared draft follows the topic until its last owner leaves" {
  new_run()
  let topic : @signals.Signal[@sfbase.Topic] = @signals.signal({
    value: Some({ "version": 1, "rev": 1, "text": "first" }), error: None, version: 1,
  })
  let base = @sfbase.made_source()
  let src : @sfbase.Source = { ..base, topic: fn(_, _) { topic.get() } }
  let first : Ref[@sfbase.Writing?] = Ref(None)
  let second : Ref[@sfbase.Writing?] = Ref(None)
  let leave_first = @signals.effect_scope(fn() { first.val = Some(@sfbase.writing(src, "shared")) })
  let leave_second = @signals.effect_scope(fn() { second.val = Some(@sfbase.writing(src, "shared")) })
  let w = first.val.unwrap()
  assert_true(physical_equal(w, second.val.unwrap()))
  leave_first()
  assert_true(topic.watched())
  topic.set({ value: Some({ "version": 2, "rev": 2, "text": "second" }), error: None, version: 2 })
  assert_eq(w.text.get(), "second")
  leave_second()
  assert_false(topic.watched())
  topic.set({ value: Some({ "version": 3, "rev": 3, "text": "third" }), error: None, version: 3 })
  assert_eq(w.text.get(), "second")
  @sfbase.writings_reset()
}

///|
test "changing one draft slot leaves another slot following its draft" {
  new_run()
  let first : @signals.Signal[@sfbase.Topic] = @signals.signal({
    value: Some({ "version": 1, "rev": 1, "text": "first" }), error: None, version: 1,
  })
  let second : @signals.Signal[@sfbase.Topic] = @signals.signal({
    value: Some({ "version": 1, "rev": 1, "text": "second" }), error: None, version: 1,
  })
  let base = @sfbase.made_source()
  let src : @sfbase.Source = {
    ..base,
    topic: fn(_, params) { if params.get("key") == Some(Json::string("first")) { first.get() } else { second.get() } },
  }
  let kept : Ref[@sfbase.Writing?] = Ref(None)
  let moved : Ref[@sfbase.Writing?] = Ref(None)
  let chosen = @signals.signal("first")
  let leave_kept = @signals.effect(fn() {
    kept.val = Some(@sfbase.writing(src, "first"))
    kept.val.unwrap().text.get() |> ignore
  })
  let leave_moved = @signals.effect(fn() {
    moved.val = Some(@sfbase.writing(src, chosen.get()))
    moved.val.unwrap().text.get() |> ignore
  })
  chosen.set("second")
  assert_true(first.watched())
  assert_true(second.watched())
  first.set({ value: Some({ "version": 2, "rev": 2, "text": "updated first" }), error: None, version: 2 })
  assert_eq(kept.val.unwrap().text.get(), "updated first")
  assert_eq(moved.val.unwrap().text.get(), "second")
  leave_moved()
  leave_kept()
  assert_false(first.watched())
  assert_false(second.watched())
  @sfbase.writings_reset()
}

///|
test "a topic received during a pending draft action is adopted when the action finishes" {
  new_run()
  let topic : @signals.Signal[@sfbase.Topic] = @signals.signal({
    value: Some({ "version": 1, "rev": 1, "text": "first", "starting": false }),
    error: None, version: 1,
  })
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let base = @sfbase.made_source(call=fn(_, _, done) { answers.push(done) })
  let src : @sfbase.Source = { ..base, topic: fn(_, _) { topic.get() } }
  let held : Ref[@sfbase.Writing?] = Ref(None)
  let leave = @signals.effect_scope(fn() { held.val = Some(@sfbase.writing(src, "pending")) })
  let w = held.val.unwrap()
  @sfbase.writing_starting(src, w, true)
  assert_true(w.starting.get())
  topic.set({
    value: Some({ "version": 2, "rev": 2, "text": "second", "starting": true, "error": "updated" }),
    error: None, version: 2,
  })
  assert_eq(w.text.get(), "first")
  assert_eq(answers.length(), 1)
  answers[0](Ok({ "version": 2 }))
  assert_eq(w.text.get(), "second")
  assert_eq(w.error.get(), "updated")
  leave()
  assert_false(topic.watched())
  @sfbase.writings_reset()
}

///|
test "out-of-order draft answers cannot adopt a core version older than the latest ack" {
  new_run()
  let topic : @signals.Signal[@sfbase.Topic] = @signals.signal({
    value: Some({ "version": 1, "rev": 1, "text": "first", "starting": false }), error: None, version: 1,
  })
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let base = @sfbase.made_source(call=fn(_, _, done) { answers.push(done) })
  let src : Source = { ..base, topic: fn(_, _) { topic.get() } }
  let w = @sfbase.writing(src, "pending-order")
  let stop = @signals.effect(fn() { w.starting.get() |> ignore })
  @sfbase.writing_starting(src, w, true)
  @sfbase.writing_error(src, w, "local")
  topic.set({ value: Some({ "version": 2, "rev": 2, "text": "too old", "starting": false }), error: None, version: 2 })
  answers[1](Ok({ "version": 3 }))
  answers[0](Ok({ "version": 2 }))
  assert_true(w.starting.get())
  assert_eq(w.error.get(), "local")
  assert_eq(w.text.get(), "first")
  topic.set({ value: Some({ "version": 3, "rev": 3, "text": "accepted", "starting": false }), error: None, version: 3 })
  assert_false(w.starting.get())
  assert_eq(w.text.get(), "accepted")
  stop()
  @sfbase.writings_reset()
}

///|
test "a failed optimistic action adopts the unchanged core value again" {
  new_run()
  let topic : @signals.Signal[@sfbase.Topic] = @signals.signal({
    value: Some({ "version": 1, "rev": 1, "text": "first", "starting": false }), error: None, version: 1,
  })
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let base = @sfbase.made_source(call=fn(_, _, done) { answers.push(done) })
  let src : Source = { ..base, topic: fn(_, _) { topic.get() } }
  let w = @sfbase.writing(src, "pending-failed")
  let stop = @signals.effect(fn() { w.starting.get() |> ignore })
  @sfbase.writing_starting(src, w, true)
  assert_true(w.starting.get())
  answers[0](Err({ "message": "failed" }))
  assert_false(w.starting.get())
  stop()
  @sfbase.writings_reset()
}

///|
test "drafts with the same key from different sources stay independent" {
  new_run()
  let first : @signals.Signal[@sfbase.Topic] = @signals.signal({
    value: Some({ "version": 1, "rev": 1, "text": "first" }), error: None, version: 1,
  })
  let second : @signals.Signal[@sfbase.Topic] = @signals.signal({
    value: Some({ "version": 1, "rev": 1, "text": "second" }), error: None, version: 1,
  })
  let base = @sfbase.made_source()
  let src_a : Source = { ..base, topic: fn(_, _) { first.get() } }
  let src_b : Source = { ..base, topic: fn(_, _) { second.get() } }
  let a = @sfbase.writing(src_a, "same")
  let b = @sfbase.writing(src_b, "same")
  assert_false(physical_equal(a, b))
  let stop_a = @signals.effect(fn() { a.text.get() |> ignore })
  let stop_b = @signals.effect(fn() { b.text.get() |> ignore })
  first.set({ value: Some({ "version": 2, "rev": 2, "text": "changed" }), error: None, version: 2 })
  assert_eq(a.text.get(), "changed")
  assert_eq(b.text.get(), "second")
  stop_a()
  stop_b()
  @sfbase.writings_reset()
}

///|
test "core text does not echo as a user edit, but a field edit is sent once" {
  new_run()
  let topic : @signals.Signal[@sfbase.Topic] = @signals.signal({
    value: Some({ "version": 1, "rev": 1, "text": "first" }), error: None, version: 1,
  })
  let calls : Array[String] = []
  let base = @sfbase.made_source(call=fn(name, params, done) {
    if name == "composer.text" { calls.push(@sfbase.text(Some(params), "text")) }
    done(Ok({ "version": 2 }))
  })
  let src : Source = { ..base, topic: fn(_, _) { topic.get() } }
  let w = @sfbase.writing(src, "no-echo")
  let stop = @signals.effect(fn() {
    let words = w.field.text()
    @sfbase.writing_text(src, w, words)
  })
  topic.set({ value: Some({ "version": 2, "rev": 2, "text": "from core" }), error: None, version: 2 })
  assert_eq(w.field.text(), "from core")
  assert_eq(calls, [])
  w.field.set("typed")
  assert_eq(calls, ["typed"])
  stop()
  @sfbase.writings_reset()
}

///|
test "a core reset ends pending draft calls and adopts the restarted core's version" {
  new_run()
  let client = @core.Client::new(fn(_) {  })
  let base = @sfbase.made_source()
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let sub = client.follow_topic(name, params~)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, params) { client.follow_topic(name, params~).waiting },
    call: fn(name, params, done) { client.call(name, params~, on_done=done) |> ignore },
    leave: fn(name, params) { client.leave_topic(name, params~) },
    release: fn(name, params) { client.release_topic(name, params~) },
  }
  let held : Ref[@sfbase.Writing?] = Ref(None)
  let stop = @signals.effect(fn() {
    let w = @sfbase.writing(src, "reset-pending")
    held.val = Some(w)
    w.starting.get() |> ignore
  })
  client.receive_json({ "id": 1, "value": { "version": 10, "rev": 2, "text": "before", "starting": false } })
  let w = held.val.unwrap()
  @sfbase.writing_error(src, w, "set")
  client.receive_json({ "id": 2, "ok": { "version": 10 } })
  client.receive_json({ "id": 1, "value": { "version": 10, "rev": 2, "text": "before", "error": "set" } })
  @sfbase.writing_starting(src, w, true)
  assert_eq(w.pending.get(), 1)
  client.reset()
  assert_eq(w.pending.get(), 0, msg="a call on the old core cannot remain pending")
  client.receive_json({ "id": 1, "value": { "version": 0, "rev": 0, "text": "after", "starting": false } })
  assert_eq(w.text.get(), "after")
  assert_false(w.starting.get())
  stop()
  @sfbase.writings_reset()
}

///|
test "a closed draft does not reopen a real client subscription" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = @sfbase.made_source()
  let src : @sfbase.Source = {
    ..base,
    topic: fn(name, params) {
      let sub = client.follow_topic(name, params~)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    leave: fn(name, params) { client.leave_topic(name, params~) },
    release: fn(name, params) { client.release_topic(name, params~) },
  }
  let params = { "key": Json::string("station:chat") }
  let held : Ref[@sfbase.Writing?] = Ref(None)
  let leave = @signals.effect_scope(fn() { held.val = Some(@sfbase.writing(src, "station:chat")) })
  let sub = client.peek_topic("composer", params~).unwrap()
  client.receive_json({
    "id": Json::number(sub.id.to_double()),
    "value": { "version": 1, "rev": 1, "text": "from core" },
  })
  assert_eq(held.val.unwrap().text.get(), "from core")
  sent.clear()
  leave()
  assert_false(sub.changes.watched())
  assert_true(sent.any(fn(s) { s.contains("\"unsubscribe\":true") }))
  assert_false(sent.any(fn(s) { s.contains("\"subscribe\":") }))
  @sfbase.writings_reset()
}

///|
test "a new chat becoming a chat lets go of the new draft" {
  new_run()
  let fresh = @signals.signal(0)
  let chat = @signals.signal(0)
  let base = fixture("home")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "composer" {
        match params.get("key") {
          Some(String("new:ws1")) => fresh.get() |> ignore
          Some(String("ws1/st1:s-c1")) => chat.get() |> ignore
          _ => ()
        }
      }
      (base.topic)(name, params)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == NewChat)
  assert_true(fresh.watched())
  app.nav.become(Chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }))
  t.run_for(@ui.move_most_ms)
  assert_true(chat.watched())
  assert_false(fresh.watched(), msg="the new draft is no longer shown")
}

///|
test "sending a new chat lets go of the draft it carried from" {
  new_run()
  let fresh = @signals.signal(0)
  let base = fixture("home")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "composer" && params.get("key") == Some(Json::string("new:ws1")) {
        fresh.get() |> ignore
      }
      (base.topic)(name, params)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0)
  t.frame()
  assert_true(app.nav.top() == NewChat)
  assert_true(fresh.watched())
  t.tap_text("做任何事")
  t.type_text("把发布说明写一下")
  tap_send(t)
  assert_true(app.nav.top() is Chat(_))
  t.run_for(@ui.move_most_ms)
  assert_false(fresh.watched(), msg="the carried draft is no longer shown")
}
