// A kept conversation given again (replay.mbt): in its order, each message in once what came before it was sent
// again, the ids of now matched to those of then.

///|
/// A run's conversation: it subscribed to accounts (id 7: asks made before), the value came; it sent a message
/// (id 9), the answer came, then the accounts changed.
let run : String =
  #|some other line of the log
  #|CORETRACE {"out":{"id":7,"subscribe":{"topic":"accounts"},"keyed":true}}
  #|CORETRACE {"in":{"id":7,"value":[]},"w":1000}
  #|CORETRACE {"out":{"id":9,"call":"chat.send","params":{"text":"hi"}}}
  #|CORETRACE {"in":{"id":9,"ok":{"sent":true}},"w":1200}
  #|CORETRACE {"in":{"id":7,"value":[{"sub":"u1"}]},"w":1300}

///|
test "what came is given in its order, the ids of now in place of those of then" {
  let r = @core.Replay::parse(run)
  let c = r.client()
  let s = c.subscribe("accounts")
  assert_eq(s.id, 1)
  // the value came before the message was sent: it is given; the answer waits for the message
  assert_eq(r.deliver(), 1)
  assert_eq(s.value.unwrap().stringify(), "[]")
  assert_eq(r.waiting(), Some("{\"id\":9,\"call\":\"chat.send\",\"params\":{\"text\":\"hi\"}}"))
  assert_eq(r.deliver(), 0)
  let answer : Ref[String] = { val: "" }
  c.call("chat.send", params={ "text": "hi" }, on_done=fn(a) {
    answer.val = match a {
      Ok(v) => v.stringify()
      Err(e) => "error " + e.stringify()
    }
  })
  |> ignore
  // one at a time: the answer, then the change
  assert_eq(r.deliver(at_most=1), 1)
  assert_eq(answer.val, "{\"sent\":true}")
  assert_eq(s.value.unwrap().stringify(), "[]")
  assert_eq(r.deliver(), 1)
  assert_eq(s.value.unwrap().stringify(), "[{\"sub\":\"u1\"}]")
  assert_eq(r.left(), 0)
  assert_eq(r.waiting(), None)
  assert_eq(r.diverged().length(), 0)
  assert_eq(r.fuzzy().length(), 0)
}

///|
test "an ask made again with other params is matched by its kind and name, and said" {
  let r = @core.Replay::parse(run)
  let c = r.client()
  let s = c.subscribe("accounts")
  let answer : Ref[Bool] = { val: false }
  c.call("chat.send", params={ "text": "hello" }, on_done=fn(a) { answer.val = a is Ok(_) })
  |> ignore
  assert_eq(r.deliver(), 3)
  assert_true(answer.val)
  assert_eq(s.version, 2)
  assert_eq(r.fuzzy().length(), 1)
  assert_true(r.fuzzy()[0].contains("hello"))
}

///|
test "where the app goes apart from the run is said, and what waits on it stays" {
  let r = @core.Replay::parse(run)
  let c = r.client()
  c.subscribe("workspaces") |> ignore
  assert_eq(r.diverged().length(), 1)
  assert_true(r.diverged()[0].contains("workspaces"))
  // the run's accounts were never asked again: nothing comes
  assert_eq(r.deliver(), 0)
  assert_eq(r.left(), 3)
  assert_true(r.waiting().unwrap().contains("accounts"))
}

///|
test "an unsubscription matched by what it names" {
  let r = @core.Replay::parse((
    #|{"out":{"id":3,"subscribe":{"topic":"threads","station":"a"},"keyed":true}}
    #|{"out":{"id":4,"subscribe":{"topic":"threads","station":"b"},"keyed":true}}
    #|{"out":{"id":4,"unsubscribe":true}}
    #|{"in":{"id":3,"value":[1]},"w":5}
  ))
  let c = r.client()
  let a = c.subscribe("threads", params={ "station": "a" })
  let b = c.subscribe("threads", params={ "station": "b" })
  // `a` is asked again but not yet let go of `b`: the value waits
  assert_eq(r.deliver(), 0)
  c.unsubscribe(b)
  assert_eq(r.deliver(), 1)
  assert_eq(a.value.unwrap().stringify(), "[1]")
  assert_eq(r.diverged().length(), 0)
}

///|
test "bytes beside an answer, as they came" {
  let r = @core.Replay::parse((
    #|{"out":{"id":1,"call":"picture","params":{"url":"u"}}}
    #|{"in":{"id":1,"ok":{}},"w":5,"b":"00ff10"}
  ))
  let c = r.client()
  let got : Ref[Bytes] = { val: b"" }
  c.call_bytes("picture", params={ "url": "u" }, on_done=fn(a) {
    match a {
      Ok((_, Some(b))) => got.val = b
      _ => ()
    }
  })
  |> ignore
  assert_eq(r.deliver(), 1)
  assert_eq(got.val, b"\x00\xff\x10")
}

///|
test "the app's core kept, then given again in its place, its wall clock with it" {
  let lines : Array[String] = []
  @core.trace_to(fn(l) { lines.push(l) })
  let s = @core.subscribe("replay-test-topic")
  assert_eq(lines.length(), 1)
  assert_true(lines[0].has_prefix("{\"out\":"))
  // what the engine would have answered, as a run keeps it
  let kept = lines[0] + "\n{\"in\":{\"id\":\{s.id},\"value\":\"here\"},\"w\":1234}"
  let r = @core.Replay::parse(kept)
  r.attach()
  // a new app over the same client: its ask goes to the replay
  @core.unsubscribe(s)
  let s2 = @core.subscribe("replay-test-topic")
  assert_eq(r.deliver(), 1)
  assert_eq(s2.value.unwrap().stringify(), "\"here\"")
  assert_eq(@core.wall_ms(), 1234.0)
  @core.Replay::detach()
  @core.trace_stop()
  assert_true(@core.wall_ms() != 1234.0)
}

///|
test "the run's calls a test does not make again, skipped with their answers" {
  let r = @core.Replay::parse(run)
  r.skip("chat.send")
  let c = r.client()
  let s = c.subscribe("accounts")
  assert_eq(r.deliver(), 2)
  assert_eq(s.version, 2)
  assert_eq(r.left(), 0)
  assert_eq(r.diverged().length(), 0)
}
