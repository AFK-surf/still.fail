///|
/// A source whose chat topic uses the real client's subscription and change signal.
fn chat_client_source(client : @core.Client) -> Source {
  let base = fixture("chat")
  {
    ..base,
    topic: fn(name, params) {
      if name == "chat" {
        let s = client.subscribe(name, params=@sfbase.core_topic_params(name, params)).followed()
        { value: s.value, error: s.error, version: s.version }
      } else {
        (base.topic)(name, params)
      }
    },
    leave: fn(name, params) {
      if name == "chat" {
        client.unsubscribe_topic(name, params=@sfbase.core_topic_params(name, params))
      } else {
        (base.leave)(name, params)
      }
    },
  }
}

///|
test "a real client follows a chat still watched as its page leaves" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = chat_client_source(client)
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }
  let params = @sfbase.core_topic_params("chat", chat_params(r))
  let seen = Ref("")
  let watcher = @signals.watch(fn() {  })
  let t = @ui.Tester::new(fn(_) {
    watcher.read(fn() {
      seen.val = match view_of_chat(src, r).0 {
        Some(v) => v.title
        None => ""
      }
    })
  })
  t.draw()
  let first = client.subscribe("chat", params~)
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": { "title": "first", "messages": [] } })
  t.draw()
  assert_eq(seen.val, "first")
  sent.clear()
  chat_left(src, r)
  t.draw()
  println("CLIENT_WATCHED_AFTER_LEAVE \{sent}")
  assert_true(sent.any(fn(s) { s.contains("\"unsubscribe\":true") }), msg="the page left the subscription")
  assert_true(sent.any(fn(s) { s.contains("\"subscribe\":") }), msg="the remaining watcher read it again")
  let again = client.subscribe("chat", params~)
  client.receive_json({ "id": Json::number(again.id.to_double()), "value": { "title": "second", "messages": [] } })
  t.draw()
  assert_eq(seen.val, "second")
  watcher.stop()
}

///|
test "a real client does not resubscribe after its last chat watcher stops" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = chat_client_source(client)
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }
  let watcher = @signals.watch(fn() {  })
  let t = @ui.Tester::new(fn(_) { watcher.read(fn() { view_of_chat(src, r) |> ignore }) })
  t.draw()
  watcher.stop()
  sent.clear()
  chat_left(src, r)
  println("CLIENT_UNWATCHED_AFTER_LEAVE \{sent}")
  assert_true(sent.any(fn(s) { s.contains("\"unsubscribe\":true") }))
  assert_false(sent.any(fn(s) { s.contains("\"subscribe\":") }), msg="no reader asked for it again")
}
