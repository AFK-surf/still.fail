// Isolated Source callback experiment: the application rows do not yet use this protocol.

///|
test "cancelling an owned early read notifies the source without ending a legacy reader" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = lease_test_source(client)
  let left : Array[String] = []
  let owned_causes = Ref(0)
  let src : Source = {
    ..base,
    leave: fn(name, params, reason) {
      left.push(name + " " + Json::object(params).stringify())
      if reason is @sfbase.TopicLeave::Owned(_) { owned_causes.val += 1 }
      (base.leave)(name, params, reason)
    },
  }
  let params : Map[String, Json] = { "station": "ws/st", "session": "s" }
  let legacy = @signals.untracked(fn() { client.follow_topic("chat", params~) })
  let early = src.lease_topic("chat", params)
  assert_true(physical_equal(legacy, client.peek_topic("chat", params~).unwrap()))
  early.cancel()
  early.cancel()
  assert_eq(left, ["chat " + Json::object(params).stringify()])
  assert_eq(owned_causes.val, 1)
  assert_true(physical_equal(legacy, client.peek_topic("chat", params~).unwrap()))
  assert_eq(lease_ended(sent, legacy.id), 0)
  client.receive_json({ "id": Json::number(legacy.id.to_double()), "value": { "text": "still here" } })
  assert_eq(@sfbase.text(legacy.value, "text"), "still here")
  client.leave_topic("chat", params~)
  assert_true(client.peek_topic("chat", params~) is None)
  assert_eq(lease_ended(sent, legacy.id), 1)
}

///|
test "a view leave notifies the source but cannot release an independent legacy reader" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = lease_test_source(client)
  let left : Array[String] = []
  let src : Source = {
    ..base,
    leave: fn(name, params, reason) {
      left.push(name)
      (base.leave)(name, params, reason)
    },
  }
  let legacy = @signals.untracked(fn() { client.follow_topic("chat") })
  let owned : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(v) { owned.val = Some(src.owned_by(v)) })
  owned.val.unwrap().topic("chat", {}).get() |> ignore
  (owned.val.unwrap().leave)("chat", {}, @sfbase.TopicLeave::Legacy)
  assert_eq(left, ["chat"])
  assert_true(physical_equal(legacy, client.peek_topic("chat").unwrap()))
  assert_eq(lease_ended(sent, legacy.id), 0)
  tree.dispose()
  client.leave_topic("chat")
  assert_true(client.peek_topic("chat") is None)
  assert_eq(lease_ended(sent, legacy.id), 1)
}

///|
test "an early read cancellation remains one-shot during a reentrant source callback" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = lease_test_source(client)
  let callbacks = Ref(0)
  let lease : Ref[@sfbase.TopicLease?] = Ref(None)
  let src : Source = {
    ..base,
    leave: fn(name, params, reason) {
      callbacks.val += 1
      lease.val.unwrap().cancel()
      (base.leave)(name, params, reason)
    },
  }
  lease.val = Some(src.lease_topic("chat", {}))
  let sub = client.peek_topic("chat").unwrap()
  lease.val.unwrap().cancel()
  assert_eq(callbacks.val, 1)
  assert_true(client.peek_topic("chat") is None)
  assert_eq(lease_ended(sent, sub.id), 1)
}

///|
test "a wrapper that observes without forwarding cannot retain a cancelled reader" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = lease_test_source(client)
  let saved : Ref[(() -> Unit)?] = Ref(None)
  let src : Source = {
    ..base,
    leave: fn(_, _, reason) {
      if reason is @sfbase.TopicLeave::Owned(stop) { saved.val = Some(stop) }
    },
  }
  let legacy = @signals.untracked(fn() { client.follow_topic("chat") })
  let reader = src.lease_topic("chat", {})
  reader.cancel()
  saved.val.unwrap()()
  saved.val.unwrap()()
  assert_true(physical_equal(legacy, client.peek_topic("chat").unwrap()))
  assert_eq(lease_ended(sent, legacy.id), 0)
  client.leave_topic("chat")
  assert_true(client.peek_topic("chat") is None)
  assert_eq(lease_ended(sent, legacy.id), 1)
}

///|
test "a view leave cannot recursively notify a forwarding callback for the same topic" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = lease_test_source(client)
  let calls = Ref(0)
  let owned : Ref[Source?] = Ref(None)
  let src : Source = {
    ..base,
    leave: fn(name, params, reason) {
      calls.val += 1
      if calls.val == 1 { (owned.val.unwrap().leave)(name, params, @sfbase.TopicLeave::Legacy) }
      (base.leave)(name, params, reason)
    },
  }
  let tree = @view.Tree::new(fn(v) { owned.val = Some(src.owned_by(v)) })
  let legacy = @signals.untracked(fn() { client.follow_topic("chat") })
  owned.val.unwrap().topic("chat", {}).get() |> ignore
  (owned.val.unwrap().leave)("chat", {}, @sfbase.TopicLeave::Legacy)
  assert_eq(calls.val, 1)
  assert_true(physical_equal(legacy, client.peek_topic("chat").unwrap()))
  client.leave_topic("chat")
  assert_true(client.peek_topic("chat") is None)
  assert_eq(lease_ended(sent, legacy.id), 1)
  tree.dispose()
}

///|
test "two readers of one view each notify when one cancellation triggers the other" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = lease_test_source(client)
  let calls = Ref(0)
  let second : Ref[@sfbase.TopicLease?] = Ref(None)
  let src : Source = {
    ..base,
    leave: fn(name, params, reason) {
      calls.val += 1
      if calls.val == 1 { second.val.unwrap().cancel() }
      (base.leave)(name, params, reason)
    },
  }
  let owned : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(v) { owned.val = Some(src.owned_by(v)) })
  let legacy = @signals.untracked(fn() { client.follow_topic("chat") })
  let first = owned.val.unwrap().lease_topic("chat", {})
  second.val = Some(owned.val.unwrap().lease_topic("chat", {}))
  first.cancel()
  assert_eq(calls.val, 2)
  assert_true(physical_equal(legacy, client.peek_topic("chat").unwrap()))
  client.leave_topic("chat")
  assert_true(client.peek_topic("chat") is None)
  assert_eq(lease_ended(sent, legacy.id), 1)
  tree.dispose()
}
