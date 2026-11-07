///|
/// A source whose chat topic uses the real client's subscription and change signal.
fn chat_client_source(client : @core.Client) -> Source {
  let base = fixture("chat")
  {
    ..base,
    topic: fn(name, params) {
      if name == "chat" {
        let s = client.follow_topic(name, params=@sfbase.core_topic_params(name, params))
        { value: s.value, error: s.error, version: s.version }
      } else {
        (base.topic)(name, params)
      }
    },
    leave: fn(name, params) {
      if name == "chat" {
        client.leave_topic(name, params=@sfbase.core_topic_params(name, params))
      } else {
        (base.leave)(name, params)
      }
    },
    release: fn(name, params) {
      if name == "chat" {
        client.release_topic(name, params=@sfbase.core_topic_params(name, params))
      } else {
        (base.release)(name, params)
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
  let first = client.peek_topic("chat", params~).unwrap()
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": { "title": "first", "messages": [] } })
  t.draw()
  assert_eq(seen.val, "first")
  sent.clear()
  chat_left(src, r)
  t.draw()
  assert_eq(sent.length(), 0, msg="the remaining watcher keeps the same subscription")
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": { "title": "second", "messages": [] } })
  t.draw()
  assert_eq(seen.val, "second")
  watcher.stop()
  assert_true(sent.any(fn(s) { s.contains("\"unsubscribe\":true") }), msg="the final watcher released the subscription")
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
  assert_true(sent.any(fn(s) { s.contains("\"unsubscribe\":true") }))
  assert_false(sent.any(fn(s) { s.contains("\"subscribe\":") }), msg="no reader asked for it again")
}
