// A real core client's messages reach the app's signal without a frame or a page copying its fields.

///|
test "two view-owned sources share a topic until the last view goes" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let first : Ref[Source?] = Ref(None)
  let second : Ref[Source?] = Ref(None)
  let first_tree = @view.Tree::new(fn(root) { first.val = Some(src.owned_by(root)) })
  let second_tree = @view.Tree::new(fn(root) { second.val = Some(src.owned_by(root)) })
  first_tree.frame(300.0, 300.0) |> ignore
  second_tree.frame(300.0, 300.0) |> ignore
  let a = first.val.unwrap()
  let b = second.val.unwrap()
  a.topic("doing", {}).get() |> ignore
  let sub = client.peek_topic("doing").unwrap()
  b.topic("doing", {}).get() |> ignore
  assert_true(physical_equal(sub, client.peek_topic("doing").unwrap()))
  assert_eq(sent.length(), 1, msg="the views share one wire subscription")
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "text": "first" } })
  assert_eq(@sfbase.text(b.topic("doing", {}).get().value, "text"), "first")
  first_tree.dispose()
  assert_true(physical_equal(sub, client.peek_topic("doing").unwrap()), msg="the second view still owns it")
  client.receive_json({ "id": Json::number(sub.id.to_double()), "delta": [{ "path": ["text"], "set": "next" }] })
  assert_eq(@sfbase.text(b.topic("doing", {}).get().value, "text"), "next")
  second_tree.dispose()
  assert_true(client.peek_topic("doing") is None, msg="the last view let it go")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "one view leaving a topic does not release another view's reader" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let first : Ref[Source?] = Ref(None)
  let second : Ref[Source?] = Ref(None)
  let first_tree = @view.Tree::new(fn(root) { first.val = Some(src.owned_by(root)) })
  let second_tree = @view.Tree::new(fn(root) { second.val = Some(src.owned_by(root)) })
  first_tree.frame(300.0, 300.0) |> ignore
  second_tree.frame(300.0, 300.0) |> ignore
  let a = first.val.unwrap()
  let b = second.val.unwrap()
  let p : Map[String, Json] = { "station": "one", "path": "two" }
  let reordered : Map[String, Json] = { "path": "two", "station": "one" }
  a.topic("doing", p).get() |> ignore
  b.topic("doing", p).get() |> ignore
  let sub = client.peek_topic("doing", params=p).unwrap()
  assert_eq(sent.length(), 1)
  assert_true(sent[0].contains("\"subscribe\":"))
  // The existing Client distinguishes different outgoing JSON field order. A view must not conflate their holds.
  a.topic("doing", reordered).get() |> ignore
  let other = client.peek_topic("doing", params=reordered).unwrap()
  assert_true(!physical_equal(sub, other))
  assert_eq(sent.length(), 2)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 2)
  (a.leave)("doing", reordered, @sfbase.TopicLeave::Legacy)
  assert_true(client.peek_topic("doing", params=reordered) is None)
  assert_true(physical_equal(sub, client.peek_topic("doing", params=p).unwrap()))
  (a.leave)("doing", p, @sfbase.TopicLeave::Legacy)
  assert_true(physical_equal(sub, client.peek_topic("doing", params=p).unwrap()))
  (b.leave)("doing", p, @sfbase.TopicLeave::Legacy)
  assert_true(client.peek_topic("doing", params=p) is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 2)
  first_tree.dispose()
  second_tree.dispose()
}

///|
test "an independent graph reader outlives a view-owned source" {
  fresh_app()
  let client = @core.Client::new(fn(_) {  })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let graph = @signals.watch(fn() {  })
  graph.read(fn() { src.topic("doing", {}).get() }) |> ignore
  owner.val.unwrap().topic("doing", {}).get() |> ignore
  let sub = client.peek_topic("doing").unwrap()
  tree.dispose()
  assert_true(physical_equal(sub, client.peek_topic("doing").unwrap()))
  graph.stop()
  assert_true(client.peek_topic("doing") is None)
}

///|
test "an untracked view reader outlives an independent base graph" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let graph = @signals.watch(fn() {  })
  graph.read(fn() { src.topic("doing", {}).get() }) |> ignore
  let sub = client.peek_topic("doing").unwrap()
  owner.val.unwrap().topic("doing", {}).get() |> ignore
  graph.stop()
  assert_true(physical_equal(sub, client.peek_topic("doing").unwrap()), msg="the view's untracked read is independently held")
  tree.dispose()
  assert_true(client.peek_topic("doing") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "a view leaving does not release an independent legacy reader" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  (src.topic_read)("doing", {}) |> ignore
  assert_true(client.peek_topic("doing") is Some(_), msg="the legacy reader subscribed")
  let sub = client.peek_topic("doing").unwrap()
  owner.val.unwrap().topic("doing", {}).get() |> ignore
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  (owner.val.unwrap().leave)("doing", {}, @sfbase.TopicLeave::Legacy)
  assert_true(client.peek_topic("doing") is Some(_), msg="the view's leave keeps the independent legacy reader")
  assert_true(physical_equal(sub, client.peek_topic("doing").unwrap()), msg="the separate legacy reader remains")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 0)
  (src.leave)("doing", {}, @sfbase.TopicLeave::Legacy)
  assert_true(client.peek_topic("doing") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
  tree.dispose()
}

///|
test "a live view-owned reader resubscribes when the client resets" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  owner.val.unwrap().topic("doing", {}).get() |> ignore
  let old = client.peek_topic("doing").unwrap()
  client.receive_json({ "id": Json::number(old.id.to_double()), "value": { "text": "before" } })
  sent.clear()
  client.reset()
  assert_eq(sent.length(), 1, msg="the live view asks the new client for the topic")
  assert_true(sent[0].contains("\"subscribe\":"))
  let current = client.peek_topic("doing").unwrap()
  assert_true(!physical_equal(old, current))
  client.unsubscribe(old)
  assert_true(physical_equal(current, client.peek_topic("doing").unwrap()))
  client.receive_json({ "id": Json::number(current.id.to_double()), "value": { "text": "after" } })
  assert_eq(@sfbase.text(owner.val.unwrap().topic("doing", {}).get().value, "text"), "after")
  tree.dispose()
  assert_true(client.peek_topic("doing") is None)
}

///|
test "an event of a view reads a topic its graph holds as it is then, held no longer than the graph holds it" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let page = owner.val.unwrap()
  // (what the page shows reads it in the graph)
  let graph = @signals.watch(fn() {  })
  graph.read(fn() { page.topic("doing", {}).get() }) |> ignore
  let sub = client.peek_topic("doing").unwrap()
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "text": "now" } })
  // (a press on it: outside any build, untracked)
  assert_eq(@sfbase.text(page.topic("doing", {}).get().value, "text"), "now", msg="the event reads it as it is then")
  graph.stop()
  assert_true(client.peek_topic("doing") is None, msg="gone with the graph, the view still alive: the event held none")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
  tree.dispose()
}

///|
test "a view-owned untracked frame read leaves no extra manual hold" {
  fresh_app()
  let client = @core.Client::new(fn(_) {  })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  @sfbase.held_build()
  owner.val.unwrap().topic("doing", {}).get() |> ignore
  @sfbase.held_end()
  assert_true(client.peek_topic("doing") is Some(_))
  tree.dispose()
  assert_true(client.peek_topic("doing") is None, msg="the view was the last owner")
}

///|
test "view owners can leave a topic through its equivalent overridden name" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let first : Ref[Source?] = Ref(None)
  let second : Ref[Source?] = Ref(None)
  let a_tree = @view.Tree::new(fn(root) { first.val = Some(src.owned_by(root)) })
  let b_tree = @view.Tree::new(fn(root) { second.val = Some(src.owned_by(root)) })
  a_tree.frame(300.0, 300.0) |> ignore
  b_tree.frame(300.0, 300.0) |> ignore
  let a = first.val.unwrap()
  let b = second.val.unwrap()
  let overridden : Map[String, Json] = { "topic": "actual", "station": "one" }
  let direct : Map[String, Json] = { "station": "one" }
  a.topic("unused", overridden).get() |> ignore
  let sub = client.peek_topic("actual", params=direct).unwrap()
  b.topic("actual", direct).get() |> ignore
  assert_eq(sent.length(), 1)
  (a.leave)("actual", direct, @sfbase.TopicLeave::Legacy)
  assert_true(physical_equal(sub, client.peek_topic("actual", params=direct).unwrap()))
  (b.leave)("unused", overridden, @sfbase.TopicLeave::Legacy)
  assert_true(client.peek_topic("actual", params=direct) is None, msg="both equivalent owners left")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
  a_tree.dispose()
  b_tree.dispose()
}

///|
test "view owners share normalized chat parameters and release independently" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = signal_client_source(client)
  let normalize = fn(name : String, params : Map[String, Json]) { @sfbase.core_topic_params(name, params) }
  let src : Source = {
    ..base,
    topic_key: fn(name, params) { @sfbase.wire_topic_key(name, normalize(name, params)) },
    topic_read: fn(name, params) { (base.topic_read)(name, normalize(name, params)) },
    waits: fn(name, params) { (base.waits)(name, normalize(name, params)) },
    leave: fn(name, params, __reason) {
      (base.leave)(name, normalize(name, params), __reason) },
    release: fn(name, params) { (base.release)(name, normalize(name, params)) },
  }
  let first : Ref[Source?] = Ref(None)
  let second : Ref[Source?] = Ref(None)
  let a_tree = @view.Tree::new(fn(root) { first.val = Some(src.owned_by(root)) })
  let b_tree = @view.Tree::new(fn(root) { second.val = Some(src.owned_by(root)) })
  a_tree.frame(300.0, 300.0) |> ignore
  b_tree.frame(300.0, 300.0) |> ignore
  let a = first.val.unwrap()
  let b = second.val.unwrap()
  let plain : Map[String, Json] = { "session": "one" }
  let compact : Map[String, Json] = { "session": "one", "compact": false }
  a.topic("chat", plain).get() |> ignore
  a.topic("chat", compact).get() |> ignore
  b.topic("chat", compact).get() |> ignore
  let expected = normalize("chat", plain)
  let sub = client.peek_topic("chat", params=expected).unwrap()
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  (a.leave)("chat", compact, @sfbase.TopicLeave::Legacy)
  assert_true(physical_equal(sub, client.peek_topic("chat", params=expected).unwrap()))
  (b.leave)("chat", plain, @sfbase.TopicLeave::Legacy)
  assert_true(client.peek_topic("chat", params=expected) is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
  a_tree.dispose()
  b_tree.dispose()
}

///|
test "a view changing parameters explicitly leaves the earlier topic" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let owned = owner.val.unwrap()
  let earlier : Map[String, Json] = { "query": "first" }
  let later : Map[String, Json] = { "query": "second" }
  owned.topic("search", earlier).get() |> ignore
  owned.topic("search", later).get() |> ignore
  (owned.leave)("search", earlier, @sfbase.TopicLeave::Legacy)
  assert_true(client.peek_topic("search", params=earlier) is None)
  assert_true(client.peek_topic("search", params=later) is Some(_))
  tree.dispose()
  assert_true(client.peek_topic("search", params=later) is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 2)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 2)
}

///|
test "a view's raw prefetch ends on cancel and coexists with another owner" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let first : Ref[Source?] = Ref(None)
  let second : Ref[Source?] = Ref(None)
  let a_tree = @view.Tree::new(fn(root) { first.val = Some(src.owned_by(root)) })
  let b_tree = @view.Tree::new(fn(root) { second.val = Some(src.owned_by(root)) })
  a_tree.frame(300.0, 300.0) |> ignore
  b_tree.frame(300.0, 300.0) |> ignore
  let a = first.val.unwrap()
  let b = second.val.unwrap()
  let params : Map[String, Json] = { "session": "one" }
  a.prefetch("chat", params) |> ignore
  assert_true(client.peek_topic("chat", params~) is Some(_))
  (a.leave)("chat", params, @sfbase.TopicLeave::Legacy)
  assert_true(client.peek_topic("chat", params~) is None, msg="cancel releases the sole prefetch")
  a.prefetch("chat", params) |> ignore
  let sub = client.peek_topic("chat", params~).unwrap()
  b.topic("chat", params).get() |> ignore
  (a.leave)("chat", params, @sfbase.TopicLeave::Legacy)
  assert_true(physical_equal(sub, client.peek_topic("chat", params~).unwrap()), msg="the other view still reads")
  b_tree.dispose()
  assert_true(client.peek_topic("chat", params~) is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 2)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 2)
  a_tree.dispose()
}

///|
test "a prefetch made inside a graph outlives that graph until cancelled" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let owned = owner.val.unwrap()
  let pressed = @signals.signal(false)
  let stop = @signals.effect(fn() {
    if pressed.get() { owned.prefetch("chat", {}) |> ignore }
  })
  pressed.set(true)
  let sub = client.peek_topic("chat").unwrap()
  stop()
  assert_true(client.peek_topic("chat") is Some(_), msg="the graph ended but the direct prefetch remains")
  assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()), msg="the explicit prefetch remains held after the graph exits")
  (owned.leave)("chat", {}, @sfbase.TopicLeave::Legacy)
  assert_true(client.peek_topic("chat") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
  tree.dispose()
}

///|
test "a base source prefetch made in a graph remains until explicitly left" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let stop = @signals.effect(fn() { src.prefetch("chat", {}) |> ignore })
  let sub = client.peek_topic("chat").unwrap()
  stop()
  assert_true(client.peek_topic("chat") is Some(_), msg="the legacy prefetch is independent of the graph")
  assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()))
  (src.leave)("chat", {}, @sfbase.TopicLeave::Legacy)
  assert_true(client.peek_topic("chat") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "a direct graph read and an independent base prefetch release differently" {
  for prefetch in [false, true] {
    fresh_app()
    let sent : Array[String] = []
    let client = @core.Client::new(fn(s) { sent.push(s) })
    let src = signal_client_source(client)
    let stop = @signals.effect(fn() {
      if prefetch { src.prefetch("chat", {}) |> ignore } else { (src.topic_read)("chat", {}) |> ignore }
    })
    let sub = client.peek_topic("chat").unwrap()
    stop()
    (src.release)("chat", {})
    if prefetch {
      assert_true(client.peek_topic("chat") is Some(_), msg="the explicit prefetch is a separate owner")
      assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()))
      assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 0)
    } else {
      assert_true(client.peek_topic("chat") is None, msg="the raw graph dependency was released")
      assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
    }
    (src.leave)("chat", {}, @sfbase.TopicLeave::Legacy)
    assert_true(client.peek_topic("chat") is None)
    assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
    assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
  }
}

///|
test "a source callback can prefetch a different topic for its view" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "outer" { owner.val.unwrap().prefetch("prefetch", {}) |> ignore }
      (base.topic_read)(name, params)
    },
  }
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let owned = owner.val.unwrap()
  let stop = @signals.effect(fn() { owned.topic("outer", {}).get() |> ignore })
  assert_true(client.peek_topic("outer") is Some(_))
  assert_true(client.peek_topic("prefetch") is Some(_))
  let prefetched = client.peek_topic("prefetch").unwrap()
  stop()
  assert_true(client.peek_topic("outer") is None, msg="the graph's topic ended")
  assert_true(client.peek_topic("prefetch") is Some(_), msg="the source callback's direct prefetch belongs to the view")
  assert_true(physical_equal(prefetched, client.peek_topic("prefetch").unwrap()))
  (owned.leave)("prefetch", {}, @sfbase.TopicLeave::Legacy)
  assert_true(client.peek_topic("prefetch") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 2)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 2)
  tree.dispose()
}

///|
test "a wrapper can prefetch before forwarding a view graph read" {
  fresh_app()
  let client = @core.Client::new(fn(_) {  })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let owned = owner.val.unwrap()
  let wrapped : Source = {
    ..owned,
    topic_read: fn(name, params) {
      if name == "outer" { owned.prefetch("prefetch", {}) |> ignore }
      (owned.topic_read)(name, params)
    },
  }
  let stop = @signals.effect(fn() { wrapped.topic("outer", {}).get() |> ignore })
  assert_true(client.peek_topic("outer") is Some(_))
  assert_true(client.peek_topic("prefetch") is Some(_))
  let prefetched = client.peek_topic("prefetch").unwrap()
  stop()
  assert_true(client.peek_topic("outer") is None, msg="the forwarded graph topic ended")
  assert_true(client.peek_topic("prefetch") is Some(_), msg="the wrapper's direct prefetch remains with its view")
  assert_true(physical_equal(prefetched, client.peek_topic("prefetch").unwrap()))
  (owned.leave)("prefetch", {}, @sfbase.TopicLeave::Legacy)
  assert_true(client.peek_topic("prefetch") is None)
  tree.dispose()
}

///|
test "a wrapper's low-level reads follow the graph without a prefetch" {
  fresh_app()
  let client = @core.Client::new(fn(_) {  })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let owned = owner.val.unwrap()
  let wrapped : Source = {
    ..owned,
    topic_read: fn(name, params) {
      if name == "outer" { (owned.topic_read)("other", {}) |> ignore }
      (owned.topic_read)(name, params)
    },
  }
  let stop = @signals.effect(fn() { wrapped.topic("outer", {}).get() |> ignore })
  assert_true(client.peek_topic("outer") is Some(_))
  assert_true(client.peek_topic("other") is Some(_))
  stop()
  assert_true(client.peek_topic("outer") is None)
  assert_true(client.peek_topic("other") is None, msg="a low-level read in this graph was not an independent prefetch")
  tree.dispose()
}

///|
test "a wrapper can forward a view graph to another topic name" {
  fresh_app()
  let client = @core.Client::new(fn(_) {  })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let owned = owner.val.unwrap()
  let wrapped : Source = {
    ..owned,
    topic_read: fn(name, params) { (owned.topic_read)(if name == "alias" { "actual" } else { name }, params) },
    waits: fn(name, params) { (owned.waits)(if name == "alias" { "actual" } else { name }, params) },
  }
  let stop = @signals.effect(fn() { wrapped.topic("alias", {}).get() |> ignore })
  assert_true(client.peek_topic("actual") is Some(_))
  stop()
  assert_true(client.peek_topic("actual") is None, msg="forwarding a graph read did not create a view prefetch")
  tree.dispose()
}

///|
test "one wire subscription preserves each source-side projection" {
  for reverse in [false, true] {
    fresh_app()
    let sent : Array[String] = []
    let client = @core.Client::new(fn(s) { sent.push(s) })
    let base = signal_client_source(client)
    let src : Source = {
      ..base,
      topic_read: fn(name, params) {
        let topic = (base.topic_read)(name, params)
        { ..topic, value: Some(Json::string(name)) }
      },
    }
    let owner : Ref[Source?] = Ref(None)
    let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
    tree.frame(300.0, 300.0) |> ignore
    let owned = owner.val.unwrap()
    let aliased : Map[String, Json] = { "topic": "actual" }
    if reverse {
      assert_eq(owned.topic("actual", {}).get().value, Some(Json::string("actual")))
      assert_eq(owned.topic("alias", aliased).get().value, Some(Json::string("alias")))
    } else {
      assert_eq(owned.topic("alias", aliased).get().value, Some(Json::string("alias")))
      assert_eq(owned.topic("actual", {}).get().value, Some(Json::string("actual")))
    }
    assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
    (owned.leave)("actual", {}, @sfbase.TopicLeave::Legacy)
    assert_true(client.peek_topic("actual") is None)
    assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
    tree.dispose()
  }
}

///|
test "a made source keeps its own topic identity" {
  fresh_app()
  let src = @sfbase.made_source(topic=fn(name, _) { Some(Json::string(name)) })
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let owned = owner.val.unwrap()
  assert_eq(owned.topic("alias", { "topic": "actual" }).get().value, Some(Json::string("alias")))
  assert_eq(owned.topic("actual", {}).get().value, Some(Json::string("actual")))
  (owned.leave)("actual", {}, @sfbase.TopicLeave::Legacy)
  assert_eq(owned.topic("alias", { "topic": "actual" }).get().value, Some(Json::string("alias")))
  tree.dispose()
}

///|
fn disposed_owned_source_case(read_kind : Int, independent_base : Bool) -> Unit raise {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let graph = @signals.watch(fn() {  })
  if independent_base {
    graph.read(fn() { src.topic("doing", {}).get() }) |> ignore
    assert_true(client.peek_topic("doing") is Some(_), msg="the base graph subscribed")
  }
  let base_sub = client.peek_topic("doing")
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let stale = owner.val.unwrap()
  tree.dispose()
  match read_kind {
    0 => (stale.topic_read)("doing", {}) |> ignore
    1 => stale.topic("doing", {}).get() |> ignore
    _ => stale.prefetch("doing", {}) |> ignore
  }
  (stale.leave)("doing", {}, @sfbase.TopicLeave::Legacy)
  if independent_base {
    assert_true(physical_equal(base_sub.unwrap(), client.peek_topic("doing").unwrap()), msg="the independent base reader keeps its original subscription")
  } else {
    assert_true(client.peek_topic("doing") is None, msg="the stale source did not subscribe")
  }
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), if independent_base { 1 } else { 0 })
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 0)
  graph.stop()
  assert_true(client.peek_topic("doing") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), if independent_base { 1 } else { 0 })
}

///|
test "a late raw read from a disposed view does not subscribe" {
  disposed_owned_source_case(0, false)
}

///|
test "a late signal read from a disposed view does not subscribe" {
  disposed_owned_source_case(1, false)
}

///|
test "a late raw read and leave do not disturb a base graph" {
  disposed_owned_source_case(0, true)
}

///|
test "a late signal read and leave do not disturb a base graph" {
  disposed_owned_source_case(1, true)
}

///|
test "a late prefetch from a disposed view does not subscribe" {
  disposed_owned_source_case(2, false)
}

///|
test "a late prefetch and leave do not disturb a base graph" {
  disposed_owned_source_case(2, true)
}

///|
test "a graph using a view's source stops following when the view is disposed" {
  fresh_app()
  let client = @core.Client::new(fn(_) {  })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let stale = owner.val.unwrap()
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(@sfbase.text(stale.topic("doing", {}).get().value, "text")) })
  let sub = client.peek_topic("doing").unwrap()
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "text": "while alive" } })
  tree.dispose()
  assert_true(client.peek_topic("doing") is None, msg="the disposed view cannot keep an external graph subscribed")
  assert_eq(seen.last(), Some(""), msg="the external graph was told the view is gone")
  stop()
}

///|
test "a view source graph drops changed parameters while the view remains" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let owned = owner.val.unwrap()
  let query = @signals.signal("first")
  let stop = @signals.effect(fn() { owned.topic("search", { "query": Json::string(query.get()) }).get() |> ignore })
  let first : Map[String, Json] = { "query": "first" }
  let second : Map[String, Json] = { "query": "second" }
  assert_true(client.peek_topic("search", params=first) is Some(_))
  query.set("second")
  assert_true(client.peek_topic("search", params=first) is None, msg="the only graph reader no longer reads the old parameters")
  assert_true(client.peek_topic("search", params=second) is Some(_))
  stop()
  assert_true(client.peek_topic("search", params=second) is None, msg="stopping the last graph reader releases its topic")
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 2)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 2)
  tree.dispose()
}

///|
test "a view source graph follows updates without another view hold" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let owned = owner.val.unwrap()
  let topic = owned.topic("doing", {})
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(@sfbase.text(topic.get().value, "text")) })
  let sub = client.peek_topic("doing").unwrap()
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "text": "one" } })
  client.receive_json({ "id": Json::number(sub.id.to_double()), "delta": [{ "path": ["text"], "set": "two" }] })
  assert_eq(seen, ["", "one", "two"])
  (owned.leave)("doing", {}, @sfbase.TopicLeave::Legacy)
  assert_true(physical_equal(sub, client.peek_topic("doing").unwrap()), msg="an active graph still reads after a view leave")
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 0)
  stop()
  assert_true(client.peek_topic("doing") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
  tree.dispose()
}

///|
test "a wrapper around a view source preserves its projection" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let owner : Ref[Source?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { owner.val = Some(src.owned_by(root)) })
  tree.frame(300.0, 300.0) |> ignore
  let owned = owner.val.unwrap()
  let wrapped : Source = {
    ..owned,
    topic_read: fn(name, params) {
      let topic = (owned.topic_read)(name, params)
      { ..topic, value: Some(Json::string(name)) }
    },
  }
  let seen : Array[Json?] = []
  let stop = @signals.effect(fn() { seen.push(wrapped.topic("doing", {}).get().value) })
  assert_eq(seen, [Some(Json::string("doing"))])
  assert_true(client.peek_topic("doing") is Some(_))
  stop()
  assert_true(client.peek_topic("doing") is None, msg="the tracked wrapper did not add a view hold")
  assert_eq(wrapped.topic("doing", {}).get().value, Some(Json::string("doing")))
  assert_true(client.peek_topic("doing") is Some(_), msg="the untracked wrapper read belongs to the view")
  tree.dispose()
  assert_true(client.peek_topic("doing") is None)
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 2)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 2)
}

///|
test "a nested view source does not give its parent an extra reader" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let parent : Ref[Source?] = Ref(None)
  let parent_tree = @view.Tree::new(fn(root) { parent.val = Some(src.owned_by(root)) })
  parent_tree.frame(300.0, 300.0) |> ignore
  let child : Ref[Source?] = Ref(None)
  let child_tree = @view.Tree::new(fn(root) { child.val = Some(parent.val.unwrap().owned_by(root)) })
  child_tree.frame(300.0, 300.0) |> ignore
  child.val.unwrap().topic("doing", {}).get() |> ignore
  assert_true(client.peek_topic("doing") is Some(_))
  child_tree.dispose()
  assert_true(client.peek_topic("doing") is None, msg="the child was the only actual reader")
  assert_eq(sent.filter(fn(s) { s.contains("\"subscribe\":") }).length(), 1)
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
  parent_tree.dispose()
}

///|
test "a nested view source becomes inert when its parent ends" {
  fresh_app()
  let client = @core.Client::new(fn(_) {  })
  let src = signal_client_source(client)
  let parent : Ref[Source?] = Ref(None)
  let parent_tree = @view.Tree::new(fn(root) { parent.val = Some(src.owned_by(root)) })
  parent_tree.frame(300.0, 300.0) |> ignore
  let child : Ref[Source?] = Ref(None)
  let child_tree = @view.Tree::new(fn(root) { child.val = Some(parent.val.unwrap().owned_by(root)) })
  child_tree.frame(300.0, 300.0) |> ignore
  let nested = child.val.unwrap()
  nested.topic("doing", {}).get() |> ignore
  assert_true(client.peek_topic("doing") is Some(_))
  parent_tree.dispose()
  assert_true(client.peek_topic("doing") is None, msg="the nested source cannot outlive its parent")
  nested.topic("doing", {}).get() |> ignore
  assert_true(client.peek_topic("doing") is None, msg="a late nested read cannot resubscribe")
  child_tree.dispose()
}

///|
test "a frame hands a topic between readers without resubscribing and releases it when none remain" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let phase = Ref(0)
  let seen = Ref("")
  let first = @signals.watch(fn() {  })
  let second = @signals.watch(fn() {  })
  let t = @ui.Tester::new(fn(_) {
    if phase.val == 0 {
      first.read(fn() { seen.val = @sfbase.text(src.topic("doing", {}).get().value, "text") })
    } else if phase.val == 1 {
      first.stop()
      second.read(fn() { seen.val = @sfbase.text(src.topic("doing", {}).get().value, "text") })
    } else {
      second.stop()
    }
  })
  t.draw()
  let sub = client.peek_topic("doing").unwrap()
  client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "text": "kept" } })
  sent.clear()
  phase.val = 1
  t.stepped()
  t.draw()
  assert_true(physical_equal(sub, client.peek_topic("doing").unwrap()), msg="the next reader kept the subscription")
  assert_eq(seen.val, "kept")
  assert_eq(sent.length(), 0, msg="the frame handover did not unsubscribe or subscribe")
  phase.val = 2
  t.stepped()
  t.draw()
  assert_true(client.peek_topic("doing") is None, msg="the frame released its last reader")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "ending a run releases its last frame reader without drawing another frame" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let t = @ui.Tester::new(fn(_) { src.topic("doing", {}).get() |> ignore })
  t.draw()
  assert_true(client.peek_topic("doing") is Some(_))
  sent.clear()
  @ui.run_let_go()
  assert_true(client.peek_topic("doing") is None, msg="the stopped run has no subscription")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
fn wide_chat_subscription_case(intermediate : Bool, leave_pending : Bool) -> Unit raise {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture_app("home")
  let chat : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let params = @sfbase.chat_params(chat)
  let core_params = @sfbase.core_topic_params("chat", params)
  let src : Source = {
    ..base,
    topic_read: fn(name, p) {
      if name != "chat" { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=@sfbase.core_topic_params(name, p))
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) {
      if name == "chat" { client.follow_topic(name, params=@sfbase.core_topic_params(name, p)).waiting } else { (base.waits)(name, p) }
    },
    leave: fn(name, p, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      if name == "chat" { client.leave_topic(name, params=@sfbase.core_topic_params(name, p)) } else { (base.leave)(name, p, @sfbase.TopicLeave::Legacy) }
    },
    release: fn(name, p) {
      if name == "chat" { client.release_topic(name, params=@sfbase.core_topic_params(name, p)) } else { (base.release)(name, p) }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.frame()
  sent.clear()
  let opened_at = t.time()
  open_chat_beside(chat)
  t.frame()
  guard client.peek_topic("chat", params=core_params) is Some(sub) else { fail("opening did not subscribe to the chat: \{Repr(sent)}") }
  assert_eq(sent.length(), 1, msg="the waiting pane keeps its first chat subscription: \{Repr(sent)}")
  let opened = try Some(@json.parse(sent[0])) catch { _ => None }
  assert_eq(@sfbase.text(@sfbase.field(opened, "subscribe"), "topic"), "chat")
  assert_eq(@sfbase.number(opened, "id"), sub.id.to_double())
  t.frame()
  assert_true(physical_equal(sub, client.peek_topic("chat", params=core_params).unwrap()))
  assert_eq(sent.length(), 1, msg="waiting another frame does not replace the subscription")
  if intermediate { t.frame_at(opened_at + 50.0) }
  t.frame_at(opened_at + 100.0)
  assert_true(t.shown_of("截图也换了") is None, msg="the chat's message has not appeared before its answer")
  let answered = if leave_pending {
    // Replace the pane before its answer. Reopening must create a new owner; a late reply to the old id is ignored.
    @sfbase.nav_over_home([])
    t.frame_at(opened_at + 116.0)
    t.frame_at(opened_at + 132.0)
    assert_true(client.peek_topic("chat", params=core_params) is None, msg="leaving while waiting releases the chat")
    assert_eq(sent.length(), 2, msg="leaving while waiting sends one unsubscribe: \{Repr(sent)}")
    let left = try Some(@json.parse(sent[1])) catch { _ => None }
    assert_true(@sfbase.flag(left, "unsubscribe"))
    assert_eq(@sfbase.number(left, "id"), sub.id.to_double())
    open_chat_beside(chat)
    t.frame_at(opened_at + 148.0)
    guard client.peek_topic("chat", params=core_params) is Some(reopened) else { fail("reopening did not subscribe: \{Repr(sent)}") }
    assert_true(reopened.id != sub.id, msg="the reopened chat has a new subscription")
    assert_eq(sent.length(), 3, msg="reopening subscribes once: \{Repr(sent)}")
    let reopened_message = try Some(@json.parse(sent[2])) catch { _ => None }
    assert_eq(@sfbase.text(@sfbase.field(reopened_message, "subscribe"), "topic"), "chat")
    assert_eq(@sfbase.number(reopened_message, "id"), reopened.id.to_double())
    let before_late = (reopened.value, reopened.error, reopened.version, reopened.waiting)
    // Deliberately distinct from the actual chat answer, so a stale delivery cannot masquerade as that answer.
    client.receive_json({ "id": Json::number(sub.id.to_double()), "value": { "lateOnly": "old subscription" } })
    t.frame_at(opened_at + 164.0)
    assert_eq((reopened.value, reopened.error, reopened.version, reopened.waiting), before_late, msg="the old reply did not change the new subscription")
    assert_true(t.shown_of("截图也换了") is None, msg="a reply for the released id cannot fill the reopened chat")
    reopened
  } else {
    sub
  }
  let value = (base.topic_read)("chat", params).value.unwrap()
  let answered_at = t.time()
  client.receive_json({ "id": Json::number(answered.id.to_double()), "value": value })
  t.frame_at(answered_at + 16.0)
  assert_eq(answered.value, Some(value), msg="the reopened subscription received the new answer")
  if intermediate { t.frame_at(answered_at + 40.0) }
  // Sample the same point after the answer whether or not an intermediate frame was drawn.
  t.frame_at(answered_at + 80.0)
  guard t.shown_of("截图也换了") is Some((_, _, w, h)) && w > 0.0 && h > 0.0 else {
    fail("the first answer's message is outside the visible area")
  }
  assert_true(t.words().iter().any(fn(word) { word.0.contains("截图也换了") && word.5 > 0.0 }), msg="the first answer's message is not transparent")
  @sfbase.nav_over_home([])
  t.frame()
  t.frame()
  assert_true(client.peek_topic("chat", params=core_params) is None, msg="the chat is released when the pane leaves")
  let n = if leave_pending { 4 } else { 2 }
  assert_eq(sent.length(), n, msg="the chat is unsubscribed once after leaving: \{Repr(sent)}")
  let last = try Some(@json.parse(sent[n - 1])) catch { _ => None }
  assert_true(@sfbase.flag(last, "unsubscribe"))
  assert_eq(@sfbase.number(last, "id"), answered.id.to_double())
  @ui.run_let_go()
}

///|
test "opening a wide chat keeps its first subscription until its answer with or without intermediate frames" {
  wide_chat_subscription_case(false, false)
  wide_chat_subscription_case(true, false)
}

///|
test "a wide chat left before its answer releases it and reopens on a new subscription" {
  wide_chat_subscription_case(false, true)
  wide_chat_subscription_case(true, true)
}

///|
test "home releases transfers while a chat covers it and reads current transfers on return" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture_app("home")
  let params : Map[String, Json] = { "workspace": Json::string("ws1") }
  let src : Source = {
    ..base,
    topic_read: fn(name, p) {
      if name != "driveTransfers" { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=p)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) {
      if name == "driveTransfers" { client.follow_topic(name, params=p).waiting } else { (base.waits)(name, p) }
    },
    leave: fn(name, p, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      if name == "driveTransfers" { client.leave_topic(name, params=p) } else { (base.leave)(name, p, @sfbase.TopicLeave::Legacy) }
    },
    release: fn(name, p) {
      if name == "driveTransfers" { client.release_topic(name, params=p) } else { (base.release)(name, p) }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.frame()
  guard client.peek_topic("driveTransfers", params~) is Some(first) else { fail("home did not subscribe to transfers") }
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": { "transfers": [{ "active": true, "copied": 25, "total": 100 }] } })
  t.frame()
  assert_true(t.query(Button, label="1 个传输 · 25%") is Some(_), msg="home shows the transfer")
  let covered_at = t.time()
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  t.frame()
  // The 390-point page slide's declared boundary is relative to the open event, independent of intermediate frames.
  let cover_boundary = covered_at + @ui.move_ms(390.0)
  t.frame_at(cover_boundary - 1.0)
  assert_true(client.peek_topic("driveTransfers", params~) is Some(_), msg="home still reads transfers just before it is covered")
  t.frame_at(cover_boundary)
  t.frame()
  assert_true(t.shown_of("做完了：") is Some(_), msg="the chat covers home")
  assert_true(client.peek_topic("driveTransfers", params~) is None, msg="home no longer reads transfers")
  let returned_at = t.time()
  nav_home()
  t.frame()
  t.frame_at(returned_at + @ui.move_ms(390.0))
  t.frame()
  guard client.peek_topic("driveTransfers", params~) is Some(second) else { fail("home did not resubscribe on return") }
  assert_true(second.id != first.id)
  client.receive_json({ "id": Json::number(second.id.to_double()), "value": { "transfers": [{ "active": true, "copied": 60, "total": 100 }] } })
  t.frame()
  assert_true(t.query(Button, label="1 个传输 · 60%") is Some(_), msg="home shows the current transfer")
  client.receive_json({ "id": Json::number(second.id.to_double()), "delta": [{ "path": ["transfers", 0, "copied"], "set": 75 }] })
  t.frame()
  assert_true(t.query(Button, label="1 个传输 · 75%") is Some(_), msg="home follows later transfer updates")
  @ui.run_let_go()
  assert_true(client.peek_topic("driveTransfers", params~) is None)
}

///|
test "reopening a chat reads the current station and follows later updates" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture_app("home")
  let params : Map[String, Json] = { "scope": "ws1" }
  let src : Source = {
    ..base,
    topic_read: fn(name, p) {
      if name != "stations" { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=p)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) {
      if name == "stations" { client.follow_topic(name, params=p).waiting } else { (base.waits)(name, p) }
    },
    leave: fn(name, p, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      if name == "stations" { client.leave_topic(name, params=p) } else { (base.leave)(name, p, @sfbase.TopicLeave::Legacy) }
    },
    release: fn(name, p) {
      if name == "stations" { client.release_topic(name, params=p) } else { (base.release)(name, p) }
    },
  }
  let chat : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_chat(chat)
  t.frame()
  guard client.peek_topic("stations", params~) is Some(first) else { fail("the chat did not subscribe to stations") }
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": [{ "station": "ws1/st1", "name": "Cedar" }] })
  t.frame()
  assert_true(t.shown_of("Cedar") is Some(_), msg="the chat shows its station")
  let left_at = t.time()
  nav_home()
  t.frame()
  let leave_boundary = left_at + @ui.move_ms(390.0)
  t.frame_at(leave_boundary - 1.0)
  assert_true(client.peek_topic("stations", params~) is Some(_), msg="the leaving chat still reads stations before its boundary")
  t.frame_at(leave_boundary)
  t.frame()
  assert_true(client.peek_topic("stations", params~) is None, msg="the chat released stations on leaving")
  open_chat(chat)
  t.frame()
  guard client.peek_topic("stations", params~) is Some(second) else { fail("the reopened chat did not subscribe to stations") }
  assert_true(second.id != first.id)
  client.receive_json({ "id": Json::number(second.id.to_double()), "value": [{ "station": "ws1/st1", "name": "Maple" }] })
  t.frame()
  assert_true(t.shown_of("Maple") is Some(_), msg="the reopened chat shows the current station")
  client.receive_json({ "id": Json::number(second.id.to_double()), "delta": [{ "path": [0, "name"], "set": "Pine" }] })
  t.frame()
  assert_true(t.shown_of("Pine") is Some(_), msg="the reopened chat follows later station updates")
  @ui.run_let_go()
  assert_true(client.peek_topic("stations", params~) is None)
}

///|
fn signal_client_source(client : @core.Client) -> Source {
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
    refresh: fn(name, params) { client.refresh_topic(name, params~) },
  }
}

///|
/// signal_client_source with its calls asked of `client` too.
fn signal_client_calls(client : @core.Client) -> Source {
  {
    ..signal_client_source(client),
    call: fn(name, params, done) {
      if @sfbase.unread_answer(done) {
        client.call(name, params~) |> ignore
      } else {
        client.call(name, params~, on_done=done) |> ignore
      }
    },
  }
}

///|
/// What of `sent` (a client's messages out) is a chats' list asked, let go of, or told its window: `sub`, `unsub`,
/// `window <rows>`, in order.
fn chats_sent(sent : Array[String]) -> Array[String] {
  let ids : Map[Int, Bool] = Map([])
  let out : Array[String] = []
  for text in sent {
    let j = @json.parse(text) catch { _ => continue }
    guard j is Object(m) && m.get("id") is Some(Number(n, ..)) else { continue }
    match (m.get("subscribe"), m.get("unsubscribe"), m.get("call")) {
      (Some(Object(t)), _, _) if t.get("topic") == Some(Json::string("chats")) => {
        ids[n.to_int()] = true
        out.push("sub")
      }
      (_, Some(True), _) if ids.contains(n.to_int()) => out.push("unsub")
      (_, _, Some(String("chats.window"))) =>
        match m.get("params") {
          Some(Object(p)) =>
            match p.get("rows") {
              Some(Number(r, ..)) => out.push("window " + r.to_int().to_string())
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
  }
  out
}

///|
/// A chats' list's value of `n` rows (in one day) and `more` past them.
fn chats_of_rows(n : Int, more : Int, marker? : String = "") -> Json {
  let items = Array::makei(n, fn(i) { Json::object({ "station": "ws1/st1", "id": Json::string("c\{i}") }) })
  { "days": [{ "daysAgo": 0, "items": Json::array(items) }], "more": Json::number(more.to_double()), "marker": Json::string(marker) }
}

///|
/// ws1's list of all its chats, holding `held` rows with `more` past them (as read by a reader), scrolled near its foot
/// (sfpages' list node: chats_grow with what it holds and has more of).
fn grow(src : Source, held : Ref[Int], more : Ref[Int]) -> Unit {
  @sfbase.chats_grow(src, "ws1", "all", held.val, more.val)
}

///|
test "a chats' list scrolled for more is told a window more on the one subscription its readers share, once till it comes" {
  @sfbase.chat_windows_reset()
  @sfbase.window_tall.val = 844.0
  let first = @sfbase.first_window(844.0)
  let step = @sfbase.window_step(844.0)
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  client.tells_before(@sfbase.chats_told_before)
  let src = signal_client_calls(client)
  let params : Map[String, Json] = { "scope": "ws1", "mine": false }
  let direct = client.subscribe("chats", params~)
  let more = Ref(-1)
  let held = Ref(0)
  let stop = @signals.effect(fn() {
    more.val = @sfbase.chats_more(src, "ws1", "all")
    held.val = @sfbase.chats_held(chats_of(src, "ws1", "all").0)
  })
  client.receive_json({ "id": Json::number(direct.id.to_double()), "value": chats_of_rows(first, 7) })
  assert_eq(more.val, 7)
  grow(src, held, more)
  // (asked again before the rows came: told nothing more)
  grow(src, held, more)
  assert_true(physical_equal(client.peek_topic("chats", params~).unwrap(), direct), msg="the one subscription remains")
  client.receive_json({ "id": Json::number(direct.id.to_double()), "value": chats_of_rows(first + 7, 0) })
  assert_eq(more.val, 0)
  // (all of it come: none asked)
  grow(src, held, more)
  client.unsubscribe(direct)
  assert_true(client.peek_topic("chats", params~) is Some(_), msg="the signal reader holds it still")
  stop()
  assert_true(client.peek_topic("chats", params~) is None, msg="it leaves with its last reader")
  assert_eq(chats_sent(sent), ["window \{first}", "sub", "window \{first + step}", "unsub"])
  @sfbase.chat_windows_reset()
}

///|
test "a chats' list's rows stay shown while its window grows: no list asked anew, none let go of" {
  @sfbase.chat_windows_reset()
  @sfbase.window_tall.val = 844.0
  let first = @sfbase.first_window(844.0)
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  client.tells_before(@sfbase.chats_told_before)
  let src = signal_client_calls(client)
  let params : Map[String, Json] = { "scope": "ws1", "mine": false }
  let shown = Ref("")
  let more = Ref(0)
  let held = Ref(0)
  let stop = @signals.effect(fn() {
    shown.val = @sfbase.text(@sfbase.chats_topic(src, "ws1").value, "marker")
    more.val = @sfbase.chats_more(src, "ws1", "all")
    held.val = @sfbase.chats_held(chats_of(src, "ws1", "all").0)
  })
  guard client.peek_topic("chats", params~) is Some(list) else { fail("the list was not followed") }
  client.receive_json({ "id": Json::number(list.id.to_double()), "value": chats_of_rows(first, 9, marker="first") })
  assert_eq(shown.val, "first")
  grow(src, held, more)
  assert_eq(shown.val, "first", msg="its rows shown while the rows added are on their way")
  client.receive_json({ "id": Json::number(list.id.to_double()), "value": chats_of_rows(first + 9, 0, marker="next") })
  assert_eq(shown.val, "next")
  assert_true(physical_equal(client.peek_topic("chats", params~).unwrap(), list))
  assert_eq(chats_sent(sent).filter(fn(m) { m == "sub" || m == "unsub" }), ["sub"])
  stop()
  assert_true(client.peek_topic("chats", params~) is None, msg="the last reader lets it go")
  @sfbase.chat_windows_reset()
}

///|
test "an untracked build read shares an existing graph reader without retaining the subscription" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let watcher = @signals.watch(fn() {  })
  watcher.read(fn() { src.topic("prefs", {}).get() |> ignore })
  @sfbase.held_build()
  @signals.untracked(fn() { src.topic("prefs", {}).get() |> ignore })
  @sfbase.held_end()
  watcher.stop()
  assert_true(client.peek_topic("prefs") is None, msg="the final graph reader releases the topic")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "refresh keeps existing signal and direct readers while replacing the wire request" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let direct = client.subscribe("filePeek")
  let live = src.topic("filePeek", {})
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(@sfbase.text(live.get().value, "text")) })
  client.receive_json({ "id": 1, "value": { "text": "before" } })
  (src.refresh)("filePeek", {})
  assert_eq(sent.length(), 3)
  assert_true(sent[1].contains("\"unsubscribe\":true"))
  assert_true(sent[2].contains("\"subscribe\""))
  assert_true(physical_equal(direct, client.peek_topic("filePeek").unwrap()))
  assert_eq(seen, ["", "before"], msg="refresh keeps the last value visible")
  client.receive_json({ "id": 1, "value": { "text": "late" } })
  client.receive_json({ "id": 2, "value": { "text": "after" } })
  assert_eq(seen, ["", "before", "after"])
  assert_eq(@sfbase.text(direct.value, "text"), "after")
  stop()
  assert_eq(sent.length(), 3, msg="the direct reader still owns the refreshed subscription")
  client.unsubscribe(direct)
  assert_eq(sent.length(), 4)
  assert_true(sent[3].contains("\"id\":2"))
}

///|
test "a direct subscriber can leave while a signal reader keeps the same topic" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let direct = client.subscribe("accounts")
  for _ in 0..<5 {
    assert_true(physical_equal(client.subscribe("accounts"), direct), msg="repeated frame reads share one direct hold")
  }
  let live = src.topic("accounts", {})
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(@sfbase.text(live.get().value, "name")) })
  client.receive_json({ "id": 1, "value": { "name": "before" } })
  client.unsubscribe(direct)
  assert_eq(sent.length(), 1, msg="a signal reader still holds the wire subscription")
  client.receive_json({ "id": 1, "value": { "name": "after" } })
  assert_eq(seen, ["", "before", "after"])
  stop()
  assert_eq(sent.length(), 2)
  assert_true(sent[1].contains("\"id\":1") && sent[1].contains("\"unsubscribe\":true"))
}

///|
test "a direct subscriber can leave while an untracked legacy reader still holds the topic" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let direct = client.subscribe("accounts")
  @sfbase.held_build()
  src.topic("accounts", {}).get().snapshot() |> ignore
  @sfbase.held_end()
  client.receive_json({ "id": 1, "value": { "name": "before" } })
  client.unsubscribe(direct)
  assert_eq(sent.length(), 1, msg="a legacy reader still holds the wire subscription")
  client.receive_json({ "id": 1, "value": { "name": "after" } })
  assert_eq(@sfbase.text(src.topic("accounts", {}).get().value, "name"), "after")
  @sfbase.held_build()
  @sfbase.held_end()
  (src.leave)("accounts", {}, @sfbase.TopicLeave::Legacy)
  assert_eq(sent.length(), 2)
  assert_true(sent[1].contains("\"id\":1") && sent[1].contains("\"unsubscribe\":true"))
}

///|
test "the existing topic entry is a signal shared across immediate frames and released after the page leaves" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  @sfbase.held_build()
  let topic : @signals.Computed[@sfbase.TopicState] = src.topic("chat", {})
  assert_true(topic.get().value is None)
  assert_eq(sent.length(), 1)
  let sub = client.peek_topic("chat").unwrap()
  @sfbase.held_end()
  client.receive_json({ "id": 1, "value": { "title": "first" } })
  @sfbase.held_build()
  let again = src.topic("chat", {})
  assert_eq(@sfbase.text(again.get().value, "title"), "first")
  assert_true(physical_equal(sub, client.peek_topic("chat").unwrap()), msg="page frames share the core subscription")
  assert_eq(sent.length(), 1, msg="the next frame does not resubscribe")
  @sfbase.held_end()
  @sfbase.held_build()
  @sfbase.held_end()
  (src.leave)("chat", {}, @sfbase.TopicLeave::Legacy)
  assert_eq(sent.length(), 2)
  assert_true(sent[1].contains("\"unsubscribe\":true"))
}

///|
test "a core topic signal follows waiting, values, deltas, errors and recovery without a frame" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let live = src.topic("chat", { "session": "one" })
  let seen : Array[String] = []
  let stop = @signals.effect(fn() {
    let state = live.get()
    let what = if state.waiting {
      "waiting"
    } else if state.error is Some(_) {
      "error"
    } else {
      @sfbase.text(state.value, "title")
    }
    seen.push(what)
  })
  assert_eq(sent.length(), 1)
  assert_eq(seen, [""])
  client.receive_json({ "id": 1, "waiting": true })
  client.receive_json({ "id": 1, "value": { "title": "one", "other": 1 } })
  client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "two" }] })
  client.receive_json({ "id": 1, "error": { "message": "offline" } })
  client.receive_json({ "id": 1, "value": { "title": "back" } })
  assert_eq(seen, ["", "waiting", "one", "two", "error", "back"])
  stop()
  live.dispose()
}

///|
test "topic signals share the core subscription and release their graph independently" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let params : Map[String, Json] = { "session": "one" }
  let first = src.topic("chat", params)
  let second = src.topic("chat", params)
  let a : Array[String] = []
  let b : Array[String] = []
  let stop_a = @signals.effect(fn() { a.push(@sfbase.text(first.get().value, "title")) })
  let stop_b = @signals.effect(fn() { b.push(@sfbase.text(second.get().value, "title")) })
  assert_eq(sent.length(), 1)
  let sub = client.peek_topic("chat", params~).unwrap()
  client.receive_json({ "id": 1, "value": { "title": "one" } })
  stop_a()
  first.dispose()
  client.receive_json({ "id": 1, "value": { "title": "two" } })
  assert_eq(a, ["", "one"])
  assert_eq(b, ["", "one", "two"])
  stop_b()
  second.dispose()
  assert_false(sub.changes.watched())
  assert_eq(sent.length(), 2)
  assert_true(sent[1].contains("\"unsubscribe\":true"))
}

///|
test "a selected field follows the topic and ignores changes to another field" {
  let client = @core.Client::new(fn(_) {  })
  let src = signal_client_source(client)
  let live = src.topic("chat", {})
  let title = @signals.computed(fn(_) { @sfbase.text(live.get().value, "title") }, same=fn(a, b) { a == b })
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(title.get()) })
  client.receive_json({ "id": 1, "value": { "title": "one", "other": 1 } })
  client.receive_json({ "id": 1, "delta": [{ "path": ["other"], "set": 2 }] })
  client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "two" }] })
  assert_eq(seen, ["", "one", "two"])
  stop()
  title.dispose()
  live.dispose()
}

///|
test "a topic signal keeps following when a direct reader leaves the shared subscription" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let params : Map[String, Json] = { "session": "one" }
  let live = src.topic("chat", params)
  params["session"] = Json::string("another")
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(@sfbase.text(live.get().value, "title")) })
  assert_true(sent[0].contains("\"session\":\"one\""))
  let direct = client.subscribe("chat", params={ "session": "one" })
  client.receive_json({ "id": 1, "value": { "title": "one" } })
  client.unsubscribe(direct)
  assert_eq(sent.length(), 1)
  client.receive_json({ "id": 1, "value": { "title": "again" } })
  assert_eq(seen, ["", "one", "again"])
  stop()
  live.dispose()
}

///|
test "a topic signal still watched when the core client resets subscribes again" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let waits : Map[Int, String] = Map([])
  let ticket = Ref(0)
  client.track(fn(what) {
    ticket.val += 1
    waits[ticket.val] = what
    ticket.val
  }, fn(id) { waits.remove(id) })
  let src = signal_client_source(client)
  let live = src.topic("chat", {})
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(@sfbase.text(live.get().value, "title")) })
  let stale = client.peek_topic("chat").unwrap()
  client.receive_json({ "id": 1, "value": { "title": "before" } })
  client.call("prefs.set") |> ignore
  sent.clear()
  client.reset()
  assert_eq(sent.length(), 1, msg="a live reader must ask the new client for its topic")
  assert_eq(waits.length(), 1, msg="only the new subscription remains awaited")
  client.unsubscribe(stale)
  assert_eq(sent.length(), 1, msg="an old handle cannot end a new subscription with the same id")
  client.receive_json({ "id": 1, "value": { "title": "after" } })
  assert_eq(seen, ["", "before", "", "after"])
  assert_eq(waits.length(), 0)
  stop()
  live.dispose()
}

///|
test "an app reset keeps a topic shared by readers that are still alive" {
  @sfbase.reset()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let first = src.topic("chat", {})
  let seen : Array[String] = []
  let stop_first = @signals.effect(fn() { seen.push(@sfbase.text(first.get().value, "title")) })
  client.receive_json({ "id": 1, "value": { "title": "before" } })
  @sfbase.reset()
  let second = src.topic("chat", {})
  let stop_second = @signals.effect(fn() { second.get() |> ignore })
  assert_eq(sent.length(), 1, msg="a live reader still owns the original subscription")
  client.receive_json({ "id": 1, "value": { "title": "after" } })
  assert_eq(seen, ["", "before", "after"])
  stop_first()
  assert_eq(sent.length(), 1, msg="the second reader still owns it")
  stop_second()
  assert_eq(sent.length(), 2, msg="the last reader released it")
}

///|
test "a retained field follows the same core topic without a frame" {
  let client = @core.Client::new(fn(_) {  })
  let src = signal_client_source(client)
  let topic = src.topic("chat", {})
  let title = @signals.computed_scoped(fn(_) { @sfbase.text(topic.get().value, "title") }, same=fn(a, b) { a == b })
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(title.get()) })
  client.receive_json({ "id": 1, "value": { "title": "one" } })
  client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "two" }] })
  assert_eq(seen, ["", "one", "two"])
  stop()
}

///|
test "a topic is subscribed once until its last signal reader leaves" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let first = src.topic("chat", { "session": "shared" })
  let second = src.topic("chat", { "session": "shared" })
  let a : Array[String] = []
  let b : Array[String] = []
  let stop_a = @signals.effect(fn() { a.push(@sfbase.text(first.get().value, "title")) })
  let stop_b = @signals.effect(fn() { b.push(@sfbase.text(second.get().value, "title")) })
  client.receive_json({ "id": 1, "value": { "title": "one" } })
  client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "two" }] })
  assert_eq(sent.length(), 1, msg="topic changes must not end and recreate its subscription")
  stop_a()
  assert_eq(sent.length(), 1, msg="another reader still needs the topic")
  client.receive_json({ "id": 1, "value": { "title": "three" } })
  assert_eq(a, ["", "one", "two"])
  assert_eq(b, ["", "one", "two", "three"])
  stop_b()
  assert_eq(sent.length(), 2, msg="the last reader leaving ends the core subscription")
  assert_true(sent[1].contains("\"unsubscribe\":true"))
}

///|
test "a topic signal read once outside the graph does not keep a subscription" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let state = src.topic("chat", { "session": "once" })
  state.get() |> ignore
  let sub = client.subscribe("chat", params={ "session": "once" })
  assert_false(sub.changes.watched(), msg="an untracked read must not leave a signal graph behind")
  assert_true(sent.any(fn(s) { s.contains("\"unsubscribe\":true") }), msg="an untracked read must not keep the core subscribed")
}

///|
test "equivalent chat params, source wrappers and old readers release one shared core subscription" {
  for old_first in [true, false] {
    let sent : Array[String] = []
    let client = @core.Client::new(fn(s) { sent.push(s) })
    let base = @sfbase.made_source()
    let src : Source = {
      ..base,
      topic_read: fn(name, params) {
        let sub = client.follow_topic(name, params=@sfbase.core_topic_params(name, params))
        { value: sub.value, error: sub.error, version: sub.version }
      },
      waits: fn(name, params) { client.follow_topic(name, params=@sfbase.core_topic_params(name, params)).waiting },
      leave: fn(name, params, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      client.leave_topic(name, params=@sfbase.core_topic_params(name, params)) },
      release: fn(name, params) { client.release_topic(name, params=@sfbase.core_topic_params(name, params)) },
    }
    let wrapped : Source = { ..src }
    let plain : Map[String, Json] = { "session": "same" }
    let compact : Map[String, Json] = { "session": "same", "compact": false }
    let legacy : Array[String] = []
    let modern : Array[String] = []
    let stop_old = @signals.effect(fn() { legacy.push(@sfbase.text(src.topic("chat", plain).get().value, "title")) })
    let first = src.topic("chat", compact)
    let second = wrapped.topic("chat", plain)
    let stop_a = @signals.effect(fn() { modern.push(@sfbase.text(first.get().value, "title")) })
    let stop_b = @signals.effect(fn() { second.get() |> ignore })
    client.receive_json({ "id": 1, "value": { "title": "before" } })
    wrapped.topic("chat", compact).get() |> ignore
    assert_eq(sent.length(), 1, msg="an untracked read must not interrupt an existing reader")
    if old_first { stop_old() } else { stop_a() }
    assert_eq(sent.length(), 1, msg="other readers still use the normalized core subscription")
    client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "after" }] })
    if old_first {
      assert_eq(modern, ["", "before", "after"])
      stop_a()
    } else {
      assert_eq(legacy, ["", "before", "after"])
      stop_old()
    }
    assert_eq(sent.length(), 1, msg="the other source wrapper is still following")
    stop_b()
    assert_eq(sent.length(), 2, msg="the final reader must release the core subscription")
    assert_true(sent[1].contains("\"unsubscribe\":true"))
  }
}

///|
test "an old untracked hold outlives a new signal reader and one-off read" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let params : Map[String, Json] = { "session": "old-holder" }
  @sfbase.held_build()
  @sfbase.hold(src, "core-signal-old-holder", "chat", params).get().snapshot() |> ignore
  @sfbase.held_end()
  client.receive_json({ "id": 1, "value": { "title": "kept" } })
  let live = src.topic("chat", params)
  live.get() |> ignore
  assert_eq(sent.length(), 1, msg="a one-off signal read cannot end the old hold")
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(@sfbase.text(live.get().value, "title")) })
  stop()
  assert_eq(sent.length(), 1, msg="leaving the new reader cannot end the old hold")
  client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "still kept" }] })
  assert_eq(@sfbase.text(@sfbase.hold(src, "core-signal-old-holder", "chat", params).get().value, "title"), "still kept")
  @sfbase.held_build()
  @sfbase.let_go(src, "core-signal-old-holder")
  assert_eq(sent.length(), 2)
  assert_true(sent[1].contains("\"unsubscribe\":true"))
}

///|
test "two old scopes and a signal reader independently hold one subscription" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let params : Map[String, Json] = { "session": "two-old" }
  @sfbase.held_build()
  @sfbase.hold(src, "first-old", "chat", params).get().snapshot() |> ignore
  @sfbase.hold(src, "second-old", "chat", params).get().snapshot() |> ignore
  let live = src.topic("chat", params)
  let stop = @signals.effect(fn() { live.get() |> ignore })
  client.receive_json({ "id": 1, "value": { "title": "before" } })
  @sfbase.held_build()
  @sfbase.let_go(src, "first-old")
  stop()
  assert_eq(sent.length(), 1, msg="the second old scope still holds the subscription")
  client.receive_json({ "id": 1, "delta": [{ "path": ["title"], "set": "after" }] })
  assert_eq(@sfbase.text(@sfbase.hold(src, "second-old", "chat", params).get().value, "title"), "after")
  @sfbase.held_build()
  @sfbase.let_go(src, "second-old")
  assert_eq(sent.length(), 2)
  assert_true(sent[1].contains("\"unsubscribe\":true"))
}

///|
test "two legacy scopes hand a subscription over within one frame" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let params : Map[String, Json] = { "session": "handover" }
  @sfbase.held_build()
  @sfbase.hold(src, "old-before", "chat", params).get().snapshot() |> ignore
  client.receive_json({ "id": 1, "value": { "title": "kept" } })
  @sfbase.let_go(src, "old-before")
  assert_eq(@sfbase.text(@sfbase.hold(src, "old-after", "chat", params).get().value, "title"), "kept")
  @sfbase.held_end()
  @sfbase.held_build()
  assert_eq(sent.length(), 1, msg="the handover must not end and recreate the topic")
  @sfbase.let_go(src, "old-after")
  assert_eq(sent.length(), 2)
}

///|
test "a legacy scope leaving in the final frame is released at that frame's end" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  @sfbase.held_build()
  @sfbase.hold(src, "last-frame", "chat", {}).get().snapshot() |> ignore
  @sfbase.let_go(src, "last-frame")
  assert_eq(sent.length(), 1)
  @sfbase.held_end()
  assert_eq(sent.length(), 2, msg="no next frame is needed to release the subscription")
}

///|
test "actual page-leave callbacks hand over and release a held topic in the same frame" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name != "held-check" { return base.topic(name, params).get().snapshot() }
      let sub = client.follow_topic(name, params~)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, params) {
      if name == "held-check" { client.follow_topic(name, params~).waiting } else { (base.waits)(name, params) }
    },
    release: fn(name, params) {
      if name == "held-check" { client.release_topic(name, params~) } else { (base.release)(name, params) }
    },
  }
  let first : ChatRef = { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }
  let second : ChatRef = { station: "ws1/st1", session: "s-c2", title: "", station_name: "" }
  let phase = Ref(0)
  let t = @ui.Tester::new(fn(c) {
    view(c, src)
    if phase.val == 0 {
      @sfbase.hold(src, @sfbase.chat_scope(first.station, first.session), "held-check", {}).get().snapshot() |> ignore
    } else if phase.val == 1 {
      @sfbase.hold(src, @sfbase.chat_scope(second.station, second.session), "held-check", {}).get().snapshot() |> ignore
    }
  }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.frame()
  client.receive_json({ "id": 1, "value": { "title": "kept" } })
  phase.val = 1
  left_pages.push(Chat(first))
  t.frame()
  assert_eq(sent.length(), 1, msg="the new page took the topic before pages-left released the old page")
  phase.val = 2
  left_pages.push(Chat(second))
  t.frame()
  assert_eq(sent.length(), 2, msg="pages-left must release it in the final frame")
  assert_true(sent[1].contains("\"unsubscribe\":true"))
}

///|
fn chat_signal_page_case(pop : Bool, intermediate : Bool) -> Unit raise {
  new_run()
  let sent : Array[String] = []
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
    topic_read: fn(name, p) {
      if !which(name, p) { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=@sfbase.core_topic_params(name, p))
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) {
      if which(name, p) { client.follow_topic(name, params=@sfbase.core_topic_params(name, p)).waiting } else { (base.waits)(name, p) }
    },
    leave: fn(name, p, __reason) {
      if name == "chat" && which(name, p) { chat_lefts.val += 1 }
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      if which(name, p) { client.leave_topic(name, params=@sfbase.core_topic_params(name, p)) } else { (base.leave)(name, p, @sfbase.TopicLeave::Legacy) }
    },
    release: fn(name, p) {
      if which(name, p) { client.release_topic(name, params=@sfbase.core_topic_params(name, p)) } else { (base.release)(name, p) }
    },
  }
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
  let chat_value = match (base.topic_read)("chat", params).value {
    Some(Object(m)) => m.copy()
    _ => fail("chat fixture is absent")
  }
  chat_value["agents"] = [{ "session": { "key": "child-session" } }]
  client.receive_json({ "id": Json::number(chat_sub.id.to_double()), "value": Json::object(chat_value) })
  t.frame()
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
  assert_eq(sent.length(), before_events, msg="the file-drop frames kept the page subscription; sent=\{Repr(sent)}")
  // (a page over the chat: another chat, by a chat's link, over it on 大屏 as a link in a message opens it,
  // Nav::push_over; popped or replaced before a frame builds it)
  let link = @sfbase.link_target({ "opens": "chat", "workspace": "ws1", "station": "st1", "chat": "s-c2" })
  assert_true(@sfbase.open_target(src, link, false, None))
  assert_true(app.nav.top() == Chat(@sfbase.chat_ref("ws1/st1", "s-c2")), msg="another chat's link opens it over the chat")
  assert_eq(sent.length(), before_events, msg="event reads share the topics from the page; before=\{before_events}, sent=\{Repr(sent)}")
  assert_true(app.nav.pages().iter().any(fn(p) { p is Chat(_) }))
  if pop {
    let start = t.time()
    home()
    assert_false(app.nav.pages().iter().any(fn(p) { p is Chat(_) }))
    assert_false(app.nav.moving(), msg="the wide navigation does not slide out")
    assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is Some(s) && physical_equal(s, chat_sub), msg="the last rendered chat still has its subscription before the next frame")
    t.frame()
    assert_true(t.shown_of("做完了：") is None, msg="the chat message is no longer visible")
    assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is None, msg="the page's last reader is released after its frame ends")
    if intermediate {
      t.frame_at(start + 100.0)
      assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is None)
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
  assert_eq(chat_lefts.val, 1, msg="one chat leave was sent")
  assert_true(client.peek_topic("chat", params=@sfbase.core_topic_params("chat", params)) is None, msg="leaving the page releases its chat")
  assert_true(physical_equal(prefs_sub, client.peek_topic("prefs").unwrap()), msg="the home page still reads prefs")
  @ui.run_let_go()
}

///|
test "a chat page's topic is shared with events and released when its pane is replaced" {
  chat_signal_page_case(false, false)
}

///|
test "a popped chat's last reader leaves without an intermediate frame" {
  chat_signal_page_case(true, false)
}

///|
test "a popped chat's last reader leaves with an intermediate frame" {
  chat_signal_page_case(true, true)
}

///|
test "a directly held accounts subscription survives source readers leaving and reset" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let direct = client.subscribe("accounts")
  let live = src.topic("accounts", {})
  let stop = @signals.effect(fn() { live.get() |> ignore })
  client.receive_json({ "id": 1, "value": { "signedIn": true } })
  stop()
  (src.leave)("accounts", {}, @sfbase.TopicLeave::Legacy)
  assert_eq(sent.length(), 1, msg="leaving the Source must not close a directly held Sub")
  client.receive_json({ "id": 1, "delta": [{ "path": ["signedIn"], "set": false }] })
  assert_false(@sfbase.flag(direct.value, "signedIn"))
  client.reset()
  let after = client.subscribe("accounts")
  assert_false(physical_equal(after, direct))
  let again = src.topic("accounts", {})
  let stop_again = @signals.effect(fn() { again.get() |> ignore })
  client.receive_json({ "id": 1, "value": { "signedIn": true } })
  stop_again()
  (src.leave)("accounts", {}, @sfbase.TopicLeave::Legacy)
  assert_true(@sfbase.flag(after.value, "signedIn"))
  assert_eq(sent.length(), 2, msg="the direct subscription after reset stays open")
  client.unsubscribe(after)
  assert_eq(sent.length(), 3)
}

///|
fn drive_place_row_case(intermediate : Bool) -> Unit raise {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = fixture("drive")
  let params : Map[String, Json] = {
    "station": "ws1/st1", "root": Json::string(@sffixture.fix_docs), "path": "长篇小说.txt",
  }
  let ours = fn(name : String, p : Map[String, Json]) {
    name == "drivePlace" && @sfbase.text(Some(Json::object(p)), "path") == "长篇小说.txt"
  }
  let src : Source = {
    ..base,
    topic_read: fn(name, p) {
      if !ours(name, p) { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=p)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) { if ours(name, p) { client.follow_topic(name, params=p).waiting } else { (base.waits)(name, p) } },
    leave: fn(name, p, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      if ours(name, p) { client.leave_topic(name, params=p) } else { (base.leave)(name, p, @sfbase.TopicLeave::Legacy) } },
    release: fn(name, p) { if ours(name, p) { client.release_topic(name, params=p) } else { (base.release)(name, p) } },
  }
  open_drive_fixture("drive")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.frame()
  guard client.peek_topic("drivePlace", params~) is Some(first) else { fail("the row did not subscribe: \{Repr(sent)}") }
  assert_eq(sent.length(), 1, msg="the row subscribes once: \{Repr(sent)}")
  let first_ask = try Some(@json.parse(sent[0])) catch { _ => None }
  assert_eq(@sfbase.text(@sfbase.field(first_ask, "subscribe"), "topic"), "drivePlace")
  assert_eq(@sfbase.number(first_ask, "id"), first.id.to_double())
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": { "at": 20, "of": 100 } })
  t.frame()
  guard t.shown_of("20%") is Some((_, _, w, h)) && w > 0.0 && h > 0.0 else { fail("the initial reading place is outside the visible area") }
  assert_true(t.words().iter().any(fn(word) { word.0.contains("20%") && word.5 > 0.0 }), msg="the initial reading place is transparent")
  let opened_at = t.time()
  t.tap_text("长篇小说.txt")
  if intermediate { t.frame_at(opened_at + 50.0) }
  t.frame_at(opened_at + 100.0)
  assert_true(physical_equal(first, client.peek_topic("drivePlace", params~).unwrap()), msg="the departing row still has its place")
  t.frame_at(opened_at + @ui.move_ms(390.0))
  t.frame()
  assert_true(client.peek_topic("drivePlace", params~) is None, msg="the covered list releases its reading place: \{Repr(sent)}")
  assert_eq(sent.length(), 2, msg="the covered list unsubscribes once: \{Repr(sent)}")
  let left = try Some(@json.parse(sent[1])) catch { _ => None }
  assert_true(@sfbase.flag(left, "unsubscribe"))
  assert_eq(@sfbase.number(left, "id"), first.id.to_double())
  let returned_at = t.time()
  t.back()
  if intermediate { t.frame_at(returned_at + 50.0) }
  t.frame_at(returned_at + @ui.move_ms(390.0))
  t.frame()
  guard client.peek_topic("drivePlace", params~) is Some(current) else { fail("returning did not read the place: \{Repr(sent)}") }
  assert_true(current.id != first.id, msg="the returned row has a new subscription: \{Repr(sent)}")
  assert_eq(sent.length(), 3, msg="the returned row subscribes once: \{Repr(sent)}")
  let again = try Some(@json.parse(sent[2])) catch { _ => None }
  assert_eq(@sfbase.text(@sfbase.field(again, "subscribe"), "topic"), "drivePlace")
  assert_eq(@sfbase.number(again, "id"), current.id.to_double())
  client.receive_json({ "id": Json::number(current.id.to_double()), "value": { "at": 75, "of": 100 } })
  t.frame()
  guard t.shown_of("75%") is Some((_, _, w, h)) && w > 0.0 && h > 0.0 else { fail("the current reading place is outside the visible area") }
  assert_true(t.words().iter().any(fn(word) { word.0.contains("75%") && word.5 > 0.0 }), msg="the current reading place is transparent")
  client.receive_json({ "id": Json::number(current.id.to_double()), "delta": [{ "path": ["at"], "set": 80 }] })
  t.frame()
  guard t.shown_of("80%") is Some((_, _, w, h)) && w > 0.0 && h > 0.0 else { fail("the updated reading place is outside the visible area") }
  assert_true(t.words().iter().any(fn(word) { word.0.contains("80%") && word.5 > 0.0 }), msg="the updated reading place is transparent")
  @ui.run_let_go()
  assert_true(client.peek_topic("drivePlace", params~) is None, msg="ending the run releases the place")
  assert_eq(sent.length(), 4, msg="ending the run unsubscribes once: \{Repr(sent)}")
  let last = try Some(@json.parse(sent[3])) catch { _ => None }
  assert_true(@sfbase.flag(last, "unsubscribe"))
  assert_eq(@sfbase.number(last, "id"), current.id.to_double())
}

///|
test "a drive row gets its current reading place after returning from the reader" {
  drive_place_row_case(false)
  drive_place_row_case(true)
}

///|
test "a chat after closing the switcher reads station changes made in the gap" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let base = @sffixture.fixture("home")
  let params : Map[String, Json] = { "scope": "ws1" }
  let src : Source = {
    ..base,
    topic_read: fn(name, p) {
      if name != "stations" { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=p)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) { if name == "stations" { client.follow_topic(name, params=p).waiting } else { (base.waits)(name, p) } },
    leave: fn(name, p, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      if name == "stations" { client.leave_topic(name, params=p) } else { (base.leave)(name, p, @sfbase.TopicLeave::Legacy) } },
    release: fn(name, p) { if name == "stations" { client.release_topic(name, params=p) } else { (base.release)(name, p) } },
    // (as a device's core: the places' lists kept as last said, which the stations a chat names its own by never take)
    reads_ahead: fn() { true },
    asks_devices: fn() { true },
    asks_outline: fn() { true },
    switches_ahead: fn() { true },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.frame()
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  guard client.peek_topic("stations", params~) is Some(first) else { fail("the switcher did not read stations: \{Repr(sent)}") }
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": [{ "station": "ws1/st1", "name": "Cedar" }] })
  t.frame()
  t.key(@ui.key_escape)
  // The switcher closes immediately; inspect its first frame after Escape.
  t.frame()
  assert_true(client.peek_topic("stations", params~) is None, msg="the switcher's reader was not released before the chat's reader: \{Repr(sent)}")
  // The server changes after unsubscribe. A late message from the old wire id must not become the new value.
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": [{ "station": "ws1/st1", "name": "Outdated" }] })
  open_chat_beside({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  t.frame()
  guard client.peek_topic("stations", params~) is Some(second) else { fail("the chat did not read stations: \{Repr(sent)}") }
  assert_true(second.id != first.id, msg="the new reader must have its own wire id")
  assert_true(second.value is None, msg="the old value must not be reused before the current answer")
  assert_true(t.shown_of("Outdated") is None, msg="a late answer to the old subscription is not shown")
  assert_true(t.shown_of("Cedar") is None, msg="the old station value is not shown while the new subscription waits")
  client.receive_json({ "id": Json::number(second.id.to_double()), "value": [{ "station": "ws1/st1", "name": "Maple" }] })
  t.frame()
  assert_true(t.shown_of("Maple") is Some(_), msg="the chat shows the station's current value")
  client.receive_json({ "id": Json::number(second.id.to_double()), "delta": [{ "path": [0, "name"], "set": "Pine" }] })
  t.frame()
  assert_true(t.shown_of("Pine") is Some(_), msg="the chat follows later station updates")
  @ui.run_let_go()
}

///|
test "a place's list let go of and asked again: kept as the core last said it, nothing made of it again when it is the same" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  client.keep(@sfbase.topic_kept)
  let src = signal_client_source(client)
  let params : Map[String, Json] = { "scope": "ws1" }
  let made = Ref(0)
  let follow = fn(seen : Array[Json?]) {
    let live = src.topic("stations", params)
    // (what a page works out of the list: done again only for another value, not for the same one said again)
    let value = @signals.computed(fn(_) { live.get().value }, same=fn(a, b) { physical_equal(a, b) })
    let stop = @signals.effect(fn() {
      made.val += 1
      seen.push(value.get())
    })
    fn() {
      stop()
      value.dispose()
      live.dispose()
    }
  }
  let first : Array[Json?] = []
  let stop = follow(first)
  client.receive_json({ "id": 1, "value": [{ "id": "a", "t": "A" }] })
  let held = first[first.length() - 1]
  stop()
  assert_true(sent[1].contains("\"keep\":true"), msg=sent[1])
  client.receive_json({ "id": 1, "v": "k:1" })
  // Asked again with its version: shown at once as it was, then the core's `same`, and nothing made again of it.
  let second : Array[Json?] = []
  let made_before = made.val
  let stop = follow(second)
  assert_true(sent[2].contains("\"have\":\"k:1\""), msg=sent[2])
  assert_true(second.length() == 1 && physical_equal(second[0], held), msg="shown at once as it was")
  client.receive_json({ "id": 2, "same": true })
  assert_eq(made.val, made_before + 1, msg="the same value said again makes nothing again")
  // Let go of while a change was on its way to it: that change is in what is kept, and shown once asked again.
  stop()
  assert_true(sent[3].contains("\"keep\":true"), msg=sent[3])
  client.receive_json({ "id": 2, "delta": [{ "path": [], "key": ["id"], "patch": "a", "ops": [{ "path": ["t"], "set": "A2" }] }] })
  client.receive_json({ "id": 2, "v": "k:2" })
  let third : Array[Json?] = []
  let stop = follow(third)
  assert_true(sent[4].contains("\"have\":\"k:2\""), msg=sent[4])
  client.receive_json({ "id": 3, "same": true })
  assert_eq(third[third.length() - 1].unwrap().stringify(), "[{\"id\":\"a\",\"t\":\"A2\"}]")
  stop()
}

///|
test "a chat let go of and asked again: nothing of it shown before the core answers, then what changed applied to what was kept" {
  fresh_app()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  client.keep(@sfbase.topic_kept)
  let src = signal_client_source(client)
  let params : Map[String, Json] = { "station": "ws/a", "session": "s1" }
  // (the id of the last chat asked, and what it was asked with)
  let asked = fn() {
    let last = sent.rev_iter().find_first(fn(s) { s.contains("\"subscribe\"") && s.contains("\"topic\":\"chat\"") }).unwrap()
    let j = @json.parse(last) catch { _ => Json::null() }
    match j {
      Object(m) =>
        match m.get("id") {
          Some(Number(d, ..)) => (d.to_int(), last)
          _ => @halt.saying("no id")
        }
      _ => @halt.saying("not JSON")
    }
  }
  let follow = fn(seen : Array[Json?]) {
    let live = src.topic("chat", params)
    let stop = @signals.effect(fn() { seen.push(live.get().value) })
    fn() {
      stop()
      live.dispose()
    }
  }
  let first : Array[Json?] = []
  let stop = follow(first)
  let (id, _) = asked()
  client.receive_json({ "id": id, "value": { "title": "A", "n": 1 } })
  stop()
  assert_true(sent.iter().any(fn(s) { s.contains("\"id\":\{id},\"unsubscribe\":true,\"keep\":true") }), msg=sent.join("\n"))
  client.receive_json({ "id": id, "v": "c:1" })
  let second : Array[Json?] = []
  let stop = follow(second)
  let (again, said) = asked()
  assert_true(again != id && said.contains("\"have\":\"c:1\""), msg=said)
  // As before it was kept: nothing shown till the core's answer, not what was kept.
  assert_true(second.iter().all(fn(v) { v is None }), msg="nothing shown early")
  client.receive_json({ "id": again, "kept": true, "delta": [{ "path": ["n"], "set": 2 }] })
  assert_eq(second[second.length() - 1].unwrap().stringify(), "{\"title\":\"A\",\"n\":2}")
  stop()
}
