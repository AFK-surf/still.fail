// A topic's keyed list read by its index (sub_list.mbt): each op of the core's one row's change, with its cause.

///|
/// A chat topic's value with `n` messages, seq 1..n.
fn chat_value(n : Int) -> String {
  let ms = Array::makei(n, fn(i) { "{\"seq\":\{i + 1},\"outgoing\":false,\"text\":\"m\{i + 1}\"}" })
  "{\"id\":1,\"value\":{\"title\":\"t\",\"messages\":[" + ms.join(",") + "]}}"
}

///|
/// The key of message `seq` from the core (not one sent from here).
fn mkey(seq : Int) -> String {
  "[\{seq},false]"
}

///|
/// A delta of one keyed op on the chat's messages: `body` its fields after the key's.
fn op(body : String) -> String {
  "{\"id\":1,\"delta\":[{\"path\":[\"messages\"],\"key\":[\"seq\",\"outgoing\"]," + body + "}]}"
}

///|
fn keys_of(l : @rows.TopicList) -> Array[String] {
  Array::makei(@signals.untracked(fn() { l.length() }), fn(i) { l.key(i) })
}

///|
test "a chat's messages read by index: put, patched, dropped, moved each one row's change, with its cause" {
  let (c, _) = recorder()
  let s = c.subscribe("chat")
  c.receive(chat_value(3)) |> ignore
  let ms = s.list(["messages"], ["seq", "outgoing"])
  assert_eq(keys_of(ms), [mkey(1), mkey(2), mkey(3)])
  let r = ms.reader()
  c.receive(op("\"why\":\"came\",\"put\":{\"seq\":4,\"outgoing\":false,\"text\":\"m4\"}")) |> ignore
  assert_eq(r.changes(), [@rows.Inserted(3, 1, Came)])
  c.receive(op("\"why\":\"came\",\"patch\":[2,false],\"ops\":[{\"path\":[\"text\"],\"set\":\"two\"}]")) |> ignore
  assert_eq(r.changes(), [@rows.Set(1, Came)])
  assert_eq(ms.value(1).stringify(), "{\"seq\":2,\"outgoing\":false,\"text\":\"two\"}")
  assert_eq(ms.version(1), 1)
  // (history come before what was there; one moved; one dropped: their keys said)
  c.receive(op("\"why\":\"history\",\"put\":{\"seq\":0,\"outgoing\":false,\"text\":\"m0\"},\"before\":[1,false]"))
  |> ignore
  c.receive(op("\"move\":[4,false],\"before\":[1,false]")) |> ignore
  c.receive(op("\"drop\":[3,false]")) |> ignore
  let cs = r.changes()
  assert_eq(cs, [
    @rows.Inserted(0, 1, History),
    @rows.Moved(mkey(4), 4, 1, Given),
    @rows.Removed(4, [mkey(3)], Given),
  ])
  assert_eq(keys_of(ms), [mkey(0), mkey(4), mkey(1), mkey(2)])
  // (where row 1 (the first message) went: carried over by the changes)
  assert_eq(@rows.index_after(cs, 0), Some(2))
  assert_eq(@rows.index_after(cs, 2), None)
  // (another field of the topic: the list not told)
  c.receive("{\"id\":1,\"delta\":[{\"path\":[\"title\"],\"set\":\"u\"}]}") |> ignore
  assert_eq(r.changes(), [])
  // (given whole: read whole, nothing moving in)
  c.receive(chat_value(2)) |> ignore
  assert_eq(r.changes(), [@rows.Whole(Given)])
  assert_eq(keys_of(ms), [mkey(1), mkey(2)])
  assert_eq(
    s.value().unwrap().stringify(),
    "{\"title\":\"t\",\"messages\":[{\"seq\":1,\"outgoing\":false,\"text\":\"m1\"},{\"seq\":2,\"outgoing\":false,\"text\":\"m2\"}]}",
  )
}

///|
test "a station that says no cause: its ops given, shown as they are" {
  let (c, _) = recorder()
  let s = c.subscribe("chat")
  c.receive(chat_value(1)) |> ignore
  let ms = s.list(["messages"], ["seq", "outgoing"])
  let r = ms.reader()
  c.receive(op("\"put\":{\"seq\":2,\"outgoing\":false,\"text\":\"m2\"}")) |> ignore
  assert_eq(r.changes(), [@rows.Inserted(1, 1, Given)])
}

///|
test "a reader fallen far behind is told to read it whole" {
  let (c, _) = recorder()
  let s = c.subscribe("chat")
  c.receive(chat_value(2)) |> ignore
  let ms = s.list(["messages"], ["seq", "outgoing"])
  let r = ms.reader()
  for i in 0..<100 {
    c.receive(op("\"why\":\"came\",\"put\":{\"seq\":9,\"outgoing\":false,\"text\":\"\{i}\"}")) |> ignore
    c.receive(op("\"why\":\"came\",\"drop\":[9,false]")) |> ignore
  }
  assert_eq(r.changes(), [@rows.Whole(Given)])
  c.receive(op("\"why\":\"came\",\"put\":{\"seq\":3,\"outgoing\":false,\"text\":\"m3\"}")) |> ignore
  assert_eq(r.changes(), [@rows.Inserted(2, 1, Came)])
}

///|
test "a row read by its key told as it is set, not as another is or as history comes before it" {
  let (c, _) = recorder()
  let s = c.subscribe("chat")
  c.receive(chat_value(3)) |> ignore
  let ms = s.list(["messages"], ["seq", "outgoing"])
  let w = @signals.watch(fn() {  })
  assert_eq(w.read(fn() { ms.version_of(mkey(2)) }), Some(0))
  c.receive(op("\"why\":\"history\",\"put\":{\"seq\":0,\"outgoing\":false,\"text\":\"m0\"},\"before\":[1,false]"))
  |> ignore
  c.receive(op("\"why\":\"came\",\"patch\":[3,false],\"ops\":[{\"path\":[\"text\"],\"set\":\"x\"}]")) |> ignore
  assert_true(!w.is_stale())
  c.receive(op("\"why\":\"came\",\"patch\":[2,false],\"ops\":[{\"path\":[\"text\"],\"set\":\"y\"}]")) |> ignore
  assert_true(w.is_stale())
  assert_eq(w.read(fn() { ms.value_of(mkey(2)).map(fn(v) { v.stringify() }) }), Some("{\"seq\":2,\"outgoing\":false,\"text\":\"y\"}"))
}

///|
test "a message come costs its list the same with 30 messages and with 3000" {
  let cost = fn(n : Int) -> Int raise {
    let (c, _) = recorder()
    let s = c.subscribe("chat")
    c.receive(chat_value(n)) |> ignore
    let ms = s.list(["messages"], ["seq", "outgoing"])
    let r = ms.reader()
    // (the last found at the end, as after the page's own last message)
    ms.find(mkey(n), near=n - 1) |> ignore
    let w = ms.work()
    c.receive(op("\"why\":\"came\",\"put\":{\"seq\":\{n + 1},\"outgoing\":false,\"text\":\"new\"}")) |> ignore
    c.receive(op("\"why\":\"came\",\"patch\":[\{n + 1},false],\"ops\":[{\"path\":[\"text\"],\"set\":\"newer\"}]"))
    |> ignore
    assert_eq(r.changes(), [@rows.Inserted(n, 1, Came), @rows.Set(n, Came)])
    ms.work() - w
  }
  assert_eq(cost(3000), cost(30))
}

///|
test "a page of history put last first goes in at once: one change, the rows read by key carried along" {
  let (c, _) = recorder()
  let s = c.subscribe("chat")
  c.receive(chat_value(3)) |> ignore
  let ms = s.list(["messages"], ["seq", "outgoing"])
  let r = ms.reader()
  let w = @signals.watch(fn() {  })
  w.read(fn() { ms.version_of(mkey(3)) }) |> ignore
  let page = Array::makei(50, fn(i) {
    let seq = -i
    let before = if i == 0 { "[1,false]" } else { "[\{seq + 1},false]" }
    "{\"path\":[\"messages\"],\"key\":[\"seq\",\"outgoing\"],\"why\":\"history\",\"put\":{\"seq\":\{seq},\"outgoing\":false,\"text\":\"h\"},\"before\":\{before}}"
  })
  let w0 = ms.work()
  c.receive("{\"id\":1,\"delta\":[" + page.join(",") + "]}") |> ignore
  assert_eq(r.changes(), [@rows.Inserted(0, 50, History)])
  assert_eq(ms.key(0), mkey(-49))
  assert_eq(ms.key(50), mkey(1))
  // (each put found its place at once, before the one put just before it; then one copy of all of it)
  assert_true(ms.work() - w0 <= 2 * 53)
  assert_true(!w.is_stale())
  // (the row read by key found where it was carried to, at once)
  let w1 = ms.work()
  assert_eq(ms.version_of(mkey(3)), Some(0))
  assert_eq(ms.work() - w1, 1)
  // (the whole value, as it is read: the lists in their places)
  match s.value() {
    Some(Object(v)) =>
      match v.get("messages") {
        Some(Array(a)) => assert_eq(a.length(), 53)
        _ => fail("no messages")
      }
    _ => fail("no value")
  }
}
