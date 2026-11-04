///|
fn history_page_work(n : Int) -> Int raise {
  let items = Array::makei(n, fn(i) { Json::object({ "id": Json::string("m\{i}") }) })
  let list = @rows.TopicList::new(["messages"], ["id"], Some({ "messages": Json::array(items) }))
  // A recent arrival leaves the search hint at the other end of the list.
  list.take({ "path": ["messages"], "key": ["id"], "put": { "id": "new" }, "why": "came" }) |> ignore
  list.come_in()
  let reader = list.reader()
  let before = list.work()
  for pair in [("h1", "m0"), ("h0", "h1")] {
    list.take({
      "path": ["messages"],
      "key": ["id"],
      "put": { "id": Json::string(pair.0) },
      "before": Json::string(pair.1),
      "why": "history",
    }) |> ignore
  }
  list.come_in()
  let work = list.work() - before
  assert_eq(list.length(), n + 3)
  assert_eq((list.key(0), list.key(1), list.key(2)), ("\"h0\"", "\"h1\"", "\"m0\""))
  assert_eq(reader.changes(), [Inserted(0, 2, History)])
  reader.let_go()
  work
}

///|
test "a page of history is added without copying the messages already in the list" {
  let small = history_page_work(30)
  let long = history_page_work(3000)
  assert_eq(long, small, msg="adding two older messages: \{small} operations with 30 existing, \{long} with 3000")
}

///|
test "a list with history at its front applies sets, moves and deletions in the same order as its deltas" {
  let old : Json = { "messages": [{ "id": "a", "v": 1 }, { "id": "b", "v": 2 }, { "id": "c", "v": 3 }] }
  let list = @rows.TopicList::new(["messages"], ["id"], Some(old))
  let ops : Array[Json] = [
    { "path": ["messages"], "key": ["id"], "put": { "id": "z", "v": 4 }, "before": "a", "why": "history" },
    { "path": ["messages"], "key": ["id"], "put": { "id": "y", "v": 5 }, "before": "z", "why": "history" },
    { "path": ["messages"], "key": ["id"], "patch": "z", "ops": [{ "path": ["v"], "set": 6 }] },
    { "path": ["messages"], "key": ["id"], "patch": "b", "ops": [{ "path": ["v"], "set": 7 }] },
    { "path": ["messages"], "key": ["id"], "move": "z", "before": "b" },
    { "path": ["messages"], "key": ["id"], "drop": "y" },
    { "path": ["messages"], "key": ["id"], "put": { "id": "x", "v": 8 } },
    { "path": ["messages"], "key": ["id"], "put": { "id": "q", "v": 9 }, "before": "b" },
    { "path": ["messages"], "key": ["id"], "drop": "b" },
    { "path": ["messages"], "key": ["id"], "move": "c", "before": "a" },
    { "path": ["messages", 1, "v"], "set": 10 },
  ]
  let mut expected = old
  for op in ops {
    expected = @rows.apply_delta(expected, [op])
    guard op is Object(fields) else { fail("not an operation") }
    list.take(fields) |> ignore
    list.come_in()
    assert_eq(list.to_json(), @rows.value_at(Some(expected), ["messages"]).unwrap(), msg="\{op}")
  }
}

///|
test "a followed message keeps its position through a history page and is told only of its own change" {
  let old : Json = { "messages": [{ "id": "a", "v": 1 }, { "id": "b", "v": 2 }] }
  let list = @rows.TopicList::new(["messages"], ["id"], Some(old))
  let watch = @signals.watch(fn() { })
  let read = fn() { list.value_of("\"b\"") }
  assert_true(watch.read(read) is Some(_))
  list.take({ "path": ["messages"], "key": ["id"], "put": { "id": "z", "v": 0 }, "before": "a", "why": "history" }) |> ignore
  list.come_in()
  assert_false(watch.is_stale())
  list.take({ "path": ["messages"], "key": ["id"], "patch": "b", "ops": [{ "path": ["v"], "set": 4 }] }) |> ignore
  assert_true(watch.is_stale())
  assert_eq(watch.read(read), Some({ "id": "b", "v": 4 }))
  watch.stop()
}
