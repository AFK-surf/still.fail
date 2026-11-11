// Isolated experiments: these leases are not yet wired to the actual application rows.

///|
fn lease_test_source(client : @core.Client) -> Source {
  let base = @sfbase.made_source()
  {
    ..base,
    topic_key: @sfbase.wire_topic_key,
    topic_read: fn(name, params) {
      let sub = client.follow_topic(name, params~)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, params) { client.follow_topic(name, params~).waiting },
    leave: fn(name, params, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      client.leave_topic(name, params~) },
    release: fn(name, params) { client.release_topic(name, params~) },
  }
}

///|
fn lease_ended(sent : Array[String], id : Int) -> Int {
  sent.filter(fn(s) {
    let message = try Some(@json.parse(s)) catch { _ => None }
    @sfbase.flag(message, "unsubscribe") && @sfbase.number(message, "id") == id.to_double()
  }).length()
}

///|
test "moving a lease keeps the same watch and makes the old handle harmless" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = lease_test_source(client)
  let source : Ref[Source?] = Ref(None)
  let target : Ref[@view.View?] = Ref(None)
  let row = @view.Tree::new(fn(v) { source.val = Some(base.owned_by(v)) })
  let root = @view.Tree::new(fn(v) { target.val = Some(v) })
  let early = source.val.unwrap().lease_topic("chat", {})
  let original = client.peek_topic("chat").unwrap()
  let moved = early.detach_to(target.val.unwrap()).unwrap()
  early.cancel()
  early.release()
  assert_true(early.read() is None)
  row.dispose()
  assert_true(client.peek_topic("chat") is Some(sub) && physical_equal(sub, original))
  assert_eq(lease_ended(sent, original.id), 0)
  client.receive_json({ "id": Json::number(original.id.to_double()), "value": { "text": "after row" } })
  assert_eq(@sfbase.text(moved.read().unwrap().value, "text"), "after row")
  root.dispose()
  assert_true(moved.read() is None)
  assert_true(client.peek_topic("chat") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(lease_ended(sent, original.id), 1)
}

///|
test "an independent lease follows a wrapper outside its view source through handover" {
  fresh_app()
  let sent : Array[String] = []
  let calls : Array[String] = []
  let outer_leaves : Array[(String, String)] = []
  let inner_leaves : Array[(String, String)] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let underlying = lease_test_source(client)
  let base : Source = {
    ..underlying,
    leave: fn(name, params, why) {
      inner_leaves.push((name, Json::object(params).stringify()))
      (underlying.leave)(name, params, why)
    },
  }
  let owner : Ref[Source?] = Ref(None)
  let target : Ref[@view.View?] = Ref(None)
  let row = @view.Tree::new(fn(v) { owner.val = Some(base.owned_by(v)) })
  let root = @view.Tree::new(fn(v) { target.val = Some(v) })
  let inner = owner.val.unwrap()
  let raw : Map[String, Json] = { "session": "s" }
  let rewrite = fn(p : Map[String, Json]) {
    let params = p.copy()
    params["scope"] = "rewritten"
    params
  }
  let wire = rewrite(raw)
  let wrapped : Source = {
    ..inner,
    topic_key: fn(_, p) { (inner.topic_key)("wire-chat", rewrite(p)) },
    topic_read: fn(_, p) {
      let value = (inner.topic_read)("wire-chat", rewrite(p))
      { ..value, value: value.value.map(fn(v) { { "text": Json::string("mapped:" + @sfbase.text(Some(v), "text")) } }) }
    },
    waits: fn(_, p) { (inner.waits)("wire-chat", rewrite(p)) },
    leave: fn(name, p, why) {
      calls.push("leave")
      outer_leaves.push((name, Json::object(p).stringify()))
      (inner.leave)("wire-chat", rewrite(p), why)
    },
    release: fn(_, p) { calls.push("release"); (inner.release)("wire-chat", rewrite(p)) },
  }
  let legacy = @signals.untracked(fn() { client.follow_topic("wire-chat", params=wire) })
  let topic = wrapped.topic("chat", raw)
  let graph = @signals.watch(fn() {  })
  graph.read(fn() { topic.get() }) |> ignore
  let old = wrapped.lease_topic("chat", raw)
  let moved = old.detach_to(target.val.unwrap()).unwrap()
  old.cancel()
  row.dispose()
  assert_true(graph.read(fn() { topic.get() }).value is None, msg="the ordinary graph still follows the old view's lifetime")
  graph.stop()
  assert_true(client.peek_topic("wire-chat", params=wire) is Some(sub) && physical_equal(sub, legacy))
  client.receive_json({ "id": Json::number(legacy.id.to_double()), "waiting": true })
  assert_true(moved.read().unwrap().waiting, msg="the lease forwards the wrapped waiting state")
  client.receive_json({ "id": Json::number(legacy.id.to_double()), "value": { "text": "next" } })
  assert_eq(@sfbase.text(moved.read().unwrap().value, "text"), "mapped:next")
  moved.cancel()
  assert_eq(calls.filter(fn(s) { s == "leave" }).length(), 1)
  assert_eq(outer_leaves, [("chat", Json::object(raw).stringify())])
  assert_eq(inner_leaves, [("wire-chat", Json::object(wire).stringify())])
  assert_eq(calls.filter(fn(s) { s == "release" }).length(), 2, msg="the graph and lease each release through the wrapper once")
  assert_true(client.peek_topic("wire-chat", params=wire) is Some(sub) && physical_equal(sub, legacy), msg="the legacy reader outlives the moved lease's cancel")
  assert_eq(lease_ended(sent, legacy.id), 0)
  client.receive_json({ "id": Json::number(legacy.id.to_double()), "value": { "text": "legacy update" } })
  assert_eq(@sfbase.text(legacy.value, "text"), "legacy update")
  client.leave_topic("wire-chat", params=wire)
  assert_true(client.peek_topic("wire-chat", params=wire) is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(lease_ended(sent, legacy.id), 1)
  root.dispose()
}

///|
test "a lease keeps the projection and remapping of a wrapper inside its view source" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = lease_test_source(client)
  let wrapped : Source = {
    ..base,
    topic_key: fn(_, p) { (base.topic_key)("renamed", p) },
    topic_read: fn(_, p) {
      let value = (base.topic_read)("renamed", p)
      { ..value, value: value.value.map(fn(v) { { "text": Json::string("inner:" + @sfbase.text(Some(v), "text")) } }) }
    },
    waits: fn(_, p) { (base.waits)("renamed", p) },
    leave: fn(_, p, why) { (base.leave)("renamed", p, why) },
    release: fn(_, p) { (base.release)("renamed", p) },
  }
  let source : Ref[Source?] = Ref(None)
  let target : Ref[@view.View?] = Ref(None)
  let row = @view.Tree::new(fn(v) { source.val = Some(wrapped.owned_by(v)) })
  let root = @view.Tree::new(fn(v) { target.val = Some(v) })
  let early = source.val.unwrap().lease_topic("chat", {})
  let sub = client.peek_topic("renamed").unwrap()
  let moved = early.detach_to(target.val.unwrap()).unwrap()
  row.dispose()
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "text": "next" } })
  assert_eq(@sfbase.text(moved.read().unwrap().value, "text"), "inner:next")
  assert_true(client.peek_topic("renamed") is Some(current) && physical_equal(current, sub))
  root.dispose()
  assert_true(client.peek_topic("renamed") is None)
  assert_eq(lease_ended(sent, sub.id), 1)
}

///|
test "destroying the destination during source cleanup cannot orphan the moved watch" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = lease_test_source(client)
  let source : Ref[Source?] = Ref(None)
  let target : Ref[@view.View?] = Ref(None)
  let row = @view.Tree::new(fn(v) { source.val = Some(base.owned_by(v)) })
  let root = @view.Tree::new(fn(v) { target.val = Some(v) })
  let inner = source.val.unwrap()
  let reentrant : Source = {
    ..inner,
    topic_lease_own: Some(fn(stop) {
      let unkeep = inner.topic_lease_own.unwrap()(stop)
      fn() { unkeep(); root.dispose() }
    }),
  }
  let early = reentrant.lease_topic("chat", {})
  let sub = client.peek_topic("chat").unwrap()
  assert_true(early.detach_to(target.val.unwrap()) is None)
  assert_true(early.read() is None)
  assert_true(client.peek_topic("chat") is None)
  assert_eq(lease_ended(sent, sub.id), 1)
  row.dispose()
}

///|
test "nested source owners end a lease until it is explicitly moved" {
  fresh_app()
  let client = @core.Client::new(fn(_) {  })
  let base = lease_test_source(client)
  let outer : Ref[Source?] = Ref(None)
  let inner : Ref[Source?] = Ref(None)
  let first = @view.Tree::new(fn(v) { outer.val = Some(base.owned_by(v)) })
  let second = @view.Tree::new(fn(v) { inner.val = Some(outer.val.unwrap().owned_by(v)) })
  let early = inner.val.unwrap().lease_topic("chat", {})
  assert_true(client.peek_topic("chat") is Some(_))
  first.dispose()
  assert_true(early.read() is None, msg="the parent source ended its lease")
  assert_true(client.peek_topic("chat") is None)
  second.dispose()
}

///|
test "a moved lease survives both nested source views and ends with its new view" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = lease_test_source(client)
  let outer : Ref[Source?] = Ref(None)
  let inner : Ref[Source?] = Ref(None)
  let destination : Ref[@view.View?] = Ref(None)
  let first = @view.Tree::new(fn(v) { outer.val = Some(base.owned_by(v)) })
  let second = @view.Tree::new(fn(v) { inner.val = Some(outer.val.unwrap().owned_by(v)) })
  let root = @view.Tree::new(fn(v) { destination.val = Some(v) })
  let old = inner.val.unwrap().lease_topic("chat", {})
  let sub = client.peek_topic("chat").unwrap()
  let moved = old.detach_to(destination.val.unwrap()).unwrap()
  first.dispose()
  second.dispose()
  old.cancel()
  assert_true(client.peek_topic("chat") is Some(current) && physical_equal(current, sub))
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "text": "nested" } })
  assert_eq(@sfbase.text(moved.read().unwrap().value, "text"), "nested")
  root.dispose()
  assert_true(moved.read() is None)
  assert_true(client.peek_topic("chat") is None)
  assert_eq(lease_ended(sent, sub.id), 1)
}

///|
test "a lease cannot move to a view that already ended" {
  fresh_app()
  let client = @core.Client::new(fn(_) {  })
  let source = lease_test_source(client)
  let target : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(v) { target.val = Some(v) })
  tree.dispose()
  let early = source.lease_topic("chat", {})
  let sub = client.peek_topic("chat").unwrap()
  assert_true(early.detach_to(target.val.unwrap()) is None)
  assert_true(early.alive())
  assert_true(client.peek_topic("chat") is Some(current) && physical_equal(current, sub))
  early.release()
  assert_true(client.peek_topic("chat") is None)
}

///|
test "two temporary readers keep one subscription until both finish" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let source = lease_test_source(client)
  let first = source.lease_topic("chat", {})
  let sub = client.peek_topic("chat").unwrap()
  let second = source.lease_topic("chat", {})
  first.release()
  assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()))
  second.release()
  assert_true(client.peek_topic("chat") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "two temporary topic readers release independently of a legacy hold" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let source = lease_test_source(client)
  let old = @signals.untracked(fn() { client.follow_topic("chat") })
  let first = source.lease_topic("chat", {})
  let second = source.lease_topic("chat", {})
  assert_true(physical_equal(old, client.peek_topic("chat").unwrap()))
  first.release()
  first.release()
  assert_true(first.read() is None)
  assert_true(physical_equal(old, client.peek_topic("chat").unwrap()))
  client.leave_topic("chat")
  assert_true(physical_equal(old, client.peek_topic("chat").unwrap()), msg="the second temporary reader outlives the legacy reader")
  client.receive_json({ "id": Json::number(old.id.to_double()), "value": { "text": "still followed" } })
  assert_eq(@sfbase.text(second.read().unwrap().value, "text"), "still followed")
  second.release()
  assert_true(client.peek_topic("chat") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "a temporary reader leaves the separate page reader and its updates intact" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let source = lease_test_source(client)
  let page : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(v) { page.val = Some(source.owned_by(v)) })
  tree.frame(300.0, 300.0) |> ignore
  page.val.unwrap().topic("chat", {}).get() |> ignore
  let sub = client.peek_topic("chat").unwrap()
  let early = source.lease_topic("chat", {})
  assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()))
  early.release()
  assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()))
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "text": "next" } })
  assert_eq(@sfbase.text(page.val.unwrap().topic("chat", {}).get().value, "text"), "next")
  tree.dispose()
  assert_true(client.peek_topic("chat") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "a temporary reader of the same view leaves that view's existing reader intact" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let source = lease_test_source(client)
  let page : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(v) { page.val = Some(source.owned_by(v)) })
  tree.frame(300.0, 300.0) |> ignore
  page.val.unwrap().topic("chat", {}).get() |> ignore
  let sub = client.peek_topic("chat").unwrap()
  let early = page.val.unwrap().lease_topic("chat", {})
  early.release()
  assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()))
  tree.dispose()
  assert_true(client.peek_topic("chat") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "an early reader made by a view ends when that view ends" {
  fresh_app()
  let client = @core.Client::new(fn(_) {  })
  let source = lease_test_source(client)
  let page : Ref[Source?] = Ref(None)
  let owner : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(v) { owner.val = Some(v); page.val = Some(source.owned_by(v)) })
  tree.frame(300.0, 300.0) |> ignore
  let early = page.val.unwrap().lease_topic("chat", {})
  early.bind_to(owner.val.unwrap())
  assert_true(client.peek_topic("chat") is Some(_))
  tree.dispose()
  assert_true(client.peek_topic("chat") is None)
  assert_true(early.read() is None, msg="disposing the bound view ended the temporary reader")
  assert_true(client.peek_topic("chat") is None, msg="a late read cannot resubscribe through the disposed view")
  early.release()
  assert_true(early.read() is None)
}

///|
test "releasing or transferring a temporary reader removes the old view cleanup" {
  fresh_app()
  let client = @core.Client::new(fn(_) {  })
  let source = lease_test_source(client)
  let first : Ref[@view.View?] = Ref(None)
  let second : Ref[@view.View?] = Ref(None)
  let tree_a = @view.Tree::new(fn(v) { first.val = Some(v) })
  let tree_b = @view.Tree::new(fn(v) { second.val = Some(v) })
  tree_a.frame(300.0, 300.0) |> ignore
  tree_b.frame(300.0, 300.0) |> ignore
  let a = first.val.unwrap()
  let b = second.val.unwrap()
  let before_a = a.owned_count()
  let before_b = b.owned_count()
  for _ in 0..<30 {
    let early = source.lease_topic("chat", {})
    early.bind_to(a)
    assert_eq(a.owned_count(), before_a + 1)
    early.release()
    assert_eq(a.owned_count(), before_a, msg="finished presses do not accumulate cleanup callbacks")
  }
  let early = source.lease_topic("chat", {})
  let sub = client.peek_topic("chat").unwrap()
  early.bind_to(a)
  early.bind_to(b)
  assert_eq(a.owned_count(), before_a)
  assert_eq(b.owned_count(), before_b + 1)
  tree_a.dispose()
  assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()), msg="transferring made the second view responsible")
  let late = source.lease_topic("chat", {})
  late.bind_to(a)
  assert_true(late.read() is None, msg="binding to a disposed view releases immediately")
  assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()), msg="the second view still owns its reader")
  tree_b.dispose()
  assert_true(early.read() is None)
  assert_true(client.peek_topic("chat") is None)
}

///|
test "a temporary reader currently reports graph release rather than legacy leave" {
  fresh_app()
  let releases = Ref(0)
  let leaves = Ref(0)
  let base = @sfbase.made_source(topic=fn(_, _) { Some({ "value": 1 }) })
  let source : Source = {
    ..base,
    leave: fn(_, _, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      leaves.val += 1 },
    release: fn(_, _) { releases.val += 1 },
  }
  let early = source.lease_topic("chat", {})
  early.release()
  assert_eq(releases.val, 1)
  assert_eq(leaves.val, 0, msg="this experimental API has not preserved the old row's leave callback")
}

///|
test "an early reader can hand its subscription to a different view before the old one ends" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let source = lease_test_source(client)
  let row : Ref[@view.View?] = Ref(None)
  let page : Ref[@view.View?] = Ref(None)
  let row_source : Ref[Source?] = Ref(None)
  let page_source : Ref[Source?] = Ref(None)
  let row_tree = @view.Tree::new(fn(v) { row.val = Some(v); row_source.val = Some(source.owned_by(v)) })
  let page_tree = @view.Tree::new(fn(v) { page.val = Some(v); page_source.val = Some(source.owned_by(v)) })
  row_tree.frame(300.0, 300.0) |> ignore
  page_tree.frame(300.0, 300.0) |> ignore
  let early = row_source.val.unwrap().lease_topic("chat", {})
  early.bind_to(row.val.unwrap())
  let sub = client.peek_topic("chat").unwrap()
  let page_reader = early.transfer_to(page_source.val.unwrap(), page.val.unwrap()).unwrap()
  // The row can receive a late cancellation after its read has moved to the page.
  early.cancel()
  assert_true(early.read() is None)
  row_tree.dispose()
  assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()), msg="the replacement was acquired before the row ended")
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "text": "page value" } })
  assert_eq(@sfbase.text(page_reader.read().unwrap().value, "text"), "page value")
  page_tree.dispose()
  assert_true(page_reader.read() is None)
  assert_true(client.peek_topic("chat") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(lease_ended(sent, sub.id), 1, msg="the original subscription was ended once")
}

///|
test "a handover to a disposed source does not drop the current reader" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let source = lease_test_source(client)
  let old_view : Ref[@view.View?] = Ref(None)
  let dead_source : Ref[Source?] = Ref(None)
  let destination : Ref[@view.View?] = Ref(None)
  let old_tree = @view.Tree::new(fn(v) { old_view.val = Some(v) })
  let dead_tree = @view.Tree::new(fn(v) { dead_source.val = Some(source.owned_by(v)) })
  let next_tree = @view.Tree::new(fn(v) { destination.val = Some(v) })
  let early = source.lease_topic("chat", {})
  early.bind_to(old_view.val.unwrap())
  let sub = client.peek_topic("chat").unwrap()
  dead_tree.dispose()
  assert_true(early.transfer_to(dead_source.val.unwrap(), destination.val.unwrap()) is None)
  assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()), msg="the old reader stays if the handover cannot follow")
  old_tree.dispose()
  assert_true(client.peek_topic("chat") is None)
  next_tree.dispose()
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "a transferred reader uses the destination source projection" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let source = lease_test_source(client)
  let projected : Source = {
    ..source,
    topic_read: fn(name, params) {
      let value = (source.topic_read)(name, params)
      if value.value is Some(_) { { ..value, value: Some({ "text": "page projection" }) } } else { value }
    },
  }
  let row : Ref[@view.View?] = Ref(None)
  let page : Ref[@view.View?] = Ref(None)
  let row_tree = @view.Tree::new(fn(v) { row.val = Some(v) })
  let page_tree = @view.Tree::new(fn(v) { page.val = Some(v) })
  let early = source.lease_topic("chat", {})
  early.bind_to(row.val.unwrap())
  let sub = client.peek_topic("chat").unwrap()
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "text": "wire value" } })
  assert_eq(@sfbase.text(early.read().unwrap().value, "text"), "wire value")
  let page_reader = early.transfer_to(projected, page.val.unwrap()).unwrap()
  assert_eq(@sfbase.text(page_reader.read().unwrap().value, "text"), "page projection")
  row_tree.dispose()
  assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()))
  page_tree.dispose()
  assert_true(client.peek_topic("chat") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "a reentrant old view disposal aborts a handover without an orphan reader" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let source = lease_test_source(client)
  let old : Ref[@view.View?] = Ref(None)
  let next : Ref[@view.View?] = Ref(None)
  let old_tree = @view.Tree::new(fn(v) { old.val = Some(v) })
  let next_tree = @view.Tree::new(fn(v) { next.val = Some(v) })
  let early = source.lease_topic("chat", {})
  early.bind_to(old.val.unwrap())
  let original = client.peek_topic("chat").unwrap()
  let fired = Ref(false)
  let replacement : Source = {
    ..source,
    topic_read: fn(name, params) {
      let value = (source.topic_read)(name, params)
      if name == "chat" && !fired.val { fired.val = true; old_tree.dispose() }
      value
    },
  }
  let handed = early.transfer_to(replacement, next.val.unwrap()) is Some(_)
  let active = early.read() is Some(_)
  next_tree.dispose()
  let still_present = client.peek_topic("chat") is Some(_)
  assert_true(fired.val && !handed && !active && !still_present, msg="fired=\{fired.val}, handed=\{handed}, active=\{active}, orphan=\{still_present}")
  assert_eq(lease_ended(sent, original.id), 1)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
}

///|
test "a reentrant destination disposal keeps the original reader until it ends" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let source = lease_test_source(client)
  let old : Ref[@view.View?] = Ref(None)
  let next : Ref[@view.View?] = Ref(None)
  let old_tree = @view.Tree::new(fn(v) { old.val = Some(v) })
  let next_tree = @view.Tree::new(fn(v) { next.val = Some(v) })
  let early = source.lease_topic("chat", {})
  early.bind_to(old.val.unwrap())
  let original = client.peek_topic("chat").unwrap()
  let fired = Ref(false)
  let replacement : Source = {
    ..source,
    topic_read: fn(name, params) {
      let value = (source.topic_read)(name, params)
      if name == "chat" && !fired.val { fired.val = true; next_tree.dispose() }
      value
    },
  }
  let handed = early.transfer_to(replacement, next.val.unwrap()) is Some(_)
  let active = early.read() is Some(_)
  let same = match client.peek_topic("chat") { Some(s) => physical_equal(s, original); None => false }
  assert_true(fired.val && !handed && active && same, msg="fired=\{fired.val}, handed=\{handed}, active=\{active}, original=\{same}")
  old_tree.dispose()
  assert_true(client.peek_topic("chat") is None)
  assert_eq(lease_ended(sent, original.id), 1)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
}

///|
test "a nested handover wins and the outer attempt leaves no orphan" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let source = lease_test_source(client)
  let old : Ref[@view.View?] = Ref(None)
  let outer : Ref[@view.View?] = Ref(None)
  let inner : Ref[@view.View?] = Ref(None)
  let old_tree = @view.Tree::new(fn(v) { old.val = Some(v) })
  let outer_tree = @view.Tree::new(fn(v) { outer.val = Some(v) })
  let inner_tree = @view.Tree::new(fn(v) { inner.val = Some(v) })
  let early : Ref[@sfbase.TopicLease?] = Ref(None)
  let nested_ok = Ref(false)
  let fired = Ref(false)
  let inner_source : Source = { ..source }
  let outer_source : Source = {
    ..source,
    topic_read: fn(name, params) {
      let value = (source.topic_read)(name, params)
      if name == "chat" && !fired.val {
        fired.val = true
        nested_ok.val = early.val.unwrap().transfer_to(inner_source, inner.val.unwrap()) is Some(_)
      }
      value
    },
  }
  let lease = source.lease_topic("chat", {})
  early.val = Some(lease)
  lease.bind_to(old.val.unwrap())
  let original = client.peek_topic("chat").unwrap()
  assert_true(lease.transfer_to(outer_source, outer.val.unwrap()) is None)
  assert_true(fired.val && nested_ok.val)
  old_tree.dispose()
  outer_tree.dispose()
  assert_true(physical_equal(original, client.peek_topic("chat").unwrap()))
  inner_tree.dispose()
  assert_true(lease.read() is None)
  assert_true(client.peek_topic("chat") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(lease_ended(sent, original.id), 1)
}

///|
test "a reader released synchronously while being read returns no live value" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = lease_test_source(client)
  let early : Ref[@sfbase.TopicLease?] = Ref(None)
  let triggered = Ref(false)
  let source : Source = {
    ..base,
    topic_read: fn(name, params) {
      let value = (base.topic_read)(name, params)
      if early.val is Some(reader) && !triggered.val {
        triggered.val = true
        reader.release()
      }
      value
    },
  }
  let reader = source.lease_topic("chat", {})
  early.val = Some(reader)
  let original = client.peek_topic("chat").unwrap()
  client.receive_json({ "id": Json::number(original.id.to_double()), "value": { "text": "new" } })
  let value = reader.read()
  let still_present = client.peek_topic("chat") is Some(_)
  assert_true(triggered.val && value is None && !still_present, msg="triggered=\{triggered.val}, returned=\{value is Some(_)}, orphan=\{still_present}")
  assert_eq(lease_ended(sent, original.id), 1)
}

///|
test "a temporary reader released in a callback retires exactly once" {
  fresh_app()
  let phase = Ref("setup")
  let events : Array[String] = []
  let client = @core.Client::new(fn(s) { events.push("\{phase.val}:wire \{s}") })
  let base = lease_test_source(client)
  let early : Ref[@sfbase.TopicLease?] = Ref(None)
  let triggered = Ref(false)
  let source : Source = {
    ..base,
    topic_read: fn(name, params) {
      events.push("\{phase.val}:read before")
      let value = (base.topic_read)(name, params)
      events.push("\{phase.val}:read after")
      if early.val is Some(reader) && !triggered.val {
        triggered.val = true
        events.push("\{phase.val}:lease release before")
        reader.release()
        events.push("\{phase.val}:lease release after")
      }
      value
    },
    release: fn(name, params) {
      events.push("\{phase.val}:graph release before")
      (base.release)(name, params)
      events.push("\{phase.val}:graph release after")
    },
  }
  let reader = source.lease_topic("chat", {})
  early.val = Some(reader)
  let original = client.peek_topic("chat").unwrap()
  phase.val = "receive"
  client.receive_json({ "id": Json::number(original.id.to_double()), "value": { "text": "new" } })
  let during_receive = triggered.val
  let after_receive = match client.peek_topic("chat") { Some(s) => physical_equal(s, original); None => false }
  phase.val = "read"
  let value = reader.read()
  let after_read = match client.peek_topic("chat") { Some(s) => physical_equal(s, original); None => false }
  phase.val = "legacy leave diagnostic"
  client.leave_topic("chat")
  let after_leave = client.peek_topic("chat") is Some(_)
  assert_true(during_receive, msg="the callback ran while receiving the update")
  assert_false(after_receive, msg="the released reader no longer retains its subscription")
  assert_true(value is None, msg="a released reader does not return a live value")
  assert_false(after_read)
  assert_false(after_leave)
  assert_eq(events.filter(fn(event) { event.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "a reader released in its explicit read returns no value and leaves no subscription" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = lease_test_source(client)
  let early : Ref[@sfbase.TopicLease?] = Ref(None)
  let triggered = Ref(false)
  let source : Source = {
    ..base,
    topic_read: fn(name, params) {
      let value = (base.topic_read)(name, params)
      if early.val is Some(reader) && !triggered.val {
        triggered.val = true
        reader.release()
      }
      value
    },
  }
  let reader = source.lease_topic("chat", {})
  let original = client.peek_topic("chat").unwrap()
  @signals.start_batch()
  client.receive_json({ "id": Json::number(original.id.to_double()), "value": { "text": "new" } })
  early.val = Some(reader)
  let was_triggered = triggered.val
  let value = reader.read()
  @signals.end_batch()
  let live = client.peek_topic("chat") is Some(_)
  assert_false(was_triggered, msg="the release callback has not run before the explicit read")
  assert_true(triggered.val && value is None && !live, msg="triggered=\{triggered.val}, returned=\{value is Some(_)}, remaining=\{live}")
  assert_eq(lease_ended(sent, original.id), 1)
}

///|
fn lease_end_during_handover(dispose_view : Bool) -> Unit raise {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = lease_test_source(client)
  let old : Ref[@view.View?] = Ref(None)
  let next : Ref[@view.View?] = Ref(None)
  let old_tree = @view.Tree::new(fn(v) { old.val = Some(v) })
  let next_tree = @view.Tree::new(fn(v) { next.val = Some(v) })
  let early : Ref[@sfbase.TopicLease?] = Ref(None)
  let released = Ref(0)
  let source : Source = {
    ..base,
    release: fn(name, params) {
      (base.release)(name, params)
      released.val += 1
      if dispose_view { next_tree.dispose() } else { early.val.unwrap().release() }
    },
  }
  let replacement : Source = { ..base }
  let reader = source.lease_topic("chat", {})
  early.val = Some(reader)
  reader.bind_to(old.val.unwrap())
  let original = client.peek_topic("chat").unwrap()
  let handed = reader.transfer_to(replacement, next.val.unwrap())
  let active = reader.read() is Some(_)
  let live = client.peek_topic("chat") is Some(_)
  if dispose_view {
    assert_true(released.val == 1 && handed is None && !active && !live, msg="disposing the new view makes the handover fail and releases it")
  } else {
    assert_true(released.val == 1 && handed is Some(_) && !active && live, msg="a late release of the old handle leaves the new reader alive")
    assert_true(physical_equal(original, client.peek_topic("chat").unwrap()))
  }
  old_tree.dispose()
  next_tree.dispose()
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(lease_ended(sent, original.id), 1)
}

///|
test "a handover reports failure if the old source release disposes the new view" {
  lease_end_during_handover(true)
}

///|
test "a handover ignores a late release of the old handle" {
  lease_end_during_handover(false)
}
