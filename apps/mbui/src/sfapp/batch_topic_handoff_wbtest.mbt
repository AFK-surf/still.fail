///|
fn batch_handoff_source(client : @core.Client) -> Source {
  let base = @sfbase.made_source()
  {
    ..base,
    topic_read: fn(name, params) {
      let sub = client.follow_topic(name, params~)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, params) { client.follow_topic(name, params~).waiting },
    release: fn(name, params) { client.release_topic(name, params~) },
  }
}

///|
test "a topic passes between readers in one batch without a wire interruption" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = batch_handoff_source(client)
  let first = @signals.watch(fn() {  })
  let second = @signals.watch(fn() {  })
  first.read(fn() { src.topic("doing", {}).get() }) |> ignore
  let original = client.peek_topic("doing").unwrap()
  client.receive_json({ "id": Json::number(original.id.to_double()), "value": { "text": "before" } })
  sent.clear()
  @signals.start_batch()
  first.stop()
  let held_until_batch_end = client.peek_topic("doing") is Some(s) && physical_equal(s, original)
  let read = second.read(fn() { src.topic("doing", {}).get() })
  @signals.end_batch()
  assert_true(held_until_batch_end, msg="the pending batch still owns the subscription handover")
  assert_true(client.peek_topic("doing") is Some(s) && physical_equal(s, original), msg="the replacement reader keeps the same subscription")
  assert_eq(@sfbase.text(read.value, "text"), "before")
  assert_eq(sent.length(), 0, msg="the handover made no subscribe or unsubscribe")
  client.receive_json({ "id": Json::number(original.id.to_double()), "value": { "text": "after" } })
  assert_eq(@sfbase.text(second.read(fn() { src.topic("doing", {}).get() }).value, "text"), "after")
  second.stop()
  assert_true(client.peek_topic("doing") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "a batch with no replacement releases the last topic reader when it ends" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = batch_handoff_source(client)
  let reader = @signals.watch(fn() {  })
  reader.read(fn() { src.topic("doing", {}).get() }) |> ignore
  let original = client.peek_topic("doing").unwrap()
  @signals.start_batch()
  reader.stop()
  let held_until_batch_end = client.peek_topic("doing") is Some(s) && physical_equal(s, original)
  @signals.end_batch()
  assert_true(held_until_batch_end)
  assert_true(client.peek_topic("doing") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "a topic passes between effects notified by the same change" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = batch_handoff_source(client)
  let first_active = @signals.signal(true)
  let stages : Array[String] = []
  let seen = Ref("")
  let stop_first = @signals.effect(fn() {
    if first_active.get() {
      src.topic("doing", {}).get() |> ignore
    } else {
      stages.push("first ended")
    }
  })
  let stop_second = @signals.effect(fn() {
    if !first_active.get() {
      stages.push("second read")
      seen.val = @sfbase.text(src.topic("doing", {}).get().value, "text")
    }
  })
  let original = client.peek_topic("doing").unwrap()
  client.receive_json({ "id": Json::number(original.id.to_double()), "value": { "text": "before" } })
  sent.clear()
  first_active.set(false)
  assert_eq(stages, ["first ended", "second read"], msg="the old reader ends before its replacement reads")
  assert_true(client.peek_topic("doing") is Some(s) && physical_equal(s, original), msg="the flush keeps the original subscription")
  assert_eq(seen.val, "before")
  assert_eq(sent.length(), 0, msg="the flush did not restart the subscription")
  client.receive_json({ "id": Json::number(original.id.to_double()), "value": { "text": "after" } })
  assert_eq(seen.val, "after")
  stop_first()
  stop_second()
  assert_true(client.peek_topic("doing") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}
