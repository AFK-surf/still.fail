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
test "a chat recorded before compact views replays without a changed ask" {
  let r = @core.Replay::parse((
    #|{"out":{"id":7,"subscribe":{"topic":"chat","station":"w/s","session":"k"},"keyed":true}}
    #|{"in":{"id":7,"value":{"title":"hello"}},"w":1}
  ))
  let c = r.client()
  let s = c.subscribe("chat", params={ "station": "w/s", "session": "k", "compact": true })
  assert_eq(r.deliver(), 1)
  assert_eq(s.value.unwrap().stringify(), "{\"title\":\"hello\"}")
  assert_eq(r.fuzzy().length(), 0)
  assert_eq(r.diverged().length(), 0)
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
test "a topic the app watches from its start (the device's downloads) that a run from before had not: not where they went apart" {
  let r = @core.Replay::parse(run)
  let c = r.client()
  let d = c.subscribe("downloads")
  let s = c.subscribe("accounts")
  assert_eq(r.diverged().length(), 0)
  // the run's own go on as it had them; the downloads have nothing
  assert_eq(r.deliver(), 1)
  assert_eq(s.value.unwrap().stringify(), "[]")
  assert_true(d.value is None)
  c.unsubscribe(d)
  assert_eq(r.diverged().length(), 0)
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

///|
test "the run's asks not made again are listed, the skipped ones aside" {
  let r = @core.Replay::parse(run)
  assert_eq(r.unmade().length(), 2)
  r.skip("chat.send")
  let c = r.client()
  assert_eq(r.unmade(), ["{\"id\":7,\"subscribe\":{\"topic\":\"accounts\"},\"keyed\":true}"])
  c.subscribe("accounts") |> ignore
  assert_eq(r.unmade().length(), 0)
}

///|
/// Two subscriptions answered at once (a's two values, b's one), then a call's answer that waits for the call.
let at_once : String =
  #|{"out":{"id":1,"subscribe":{"topic":"a"},"keyed":true}}
  #|{"out":{"id":2,"subscribe":{"topic":"b"},"keyed":true}}
  #|{"in":{"id":1,"value":1},"w":10}
  #|{"in":{"id":1,"value":2},"w":11}
  #|{"in":{"id":2,"value":1},"w":12}
  #|{"out":{"id":3,"call":"c"}}
  #|{"in":{"id":3,"ok":true},"w":13}

///|
/// The order the values of a and b came in, one a delivery, under `seed`.
fn order_of(seed : UInt) -> String raise {
  let r = @core.Replay::parse(at_once)
  r.shuffle(seed)
  let c = r.client()
  let seen = []
  let a = c.subscribe("a")
  let b = c.subscribe("b")
  while r.deliver(at_most=1) == 1 {
    seen.push("a\{a.value.map(fn(v) { v.stringify() }).unwrap_or("-")} b\{b.value.map(fn(v) { v.stringify() }).unwrap_or("-")}")
  }
  // the call's answer never comes before the call
  assert_eq(r.left(), 1)
  assert_true(r.waiting().unwrap().contains("\"c\""))
  seen.join(", ")
}

///|
test "shuffled: what may come at once in an order drawn from the seed, each ask's own in theirs" {
  // as it came
  assert_eq(order_of(0), "a1 b-, a2 b-, a2 b1")
  // every seed: all three given, a's 1 before its 2; the same seed, the same order
  let orders = []
  for seed in 1U..<20U {
    let o = order_of(seed)
    assert_true(o.has_suffix("a2 b1") || o == "a1 b-, a1 b1, a2 b1" || o == "a- b1, a1 b1, a2 b1")
    assert_eq(order_of(seed), o)
    if !orders.contains(o) {
      orders.push(o)
    }
  }
  // and more than one order among them
  assert_true(orders.length() > 1)
}

///|
test "an ask the run's timing made, dropped with what came for it" {
  let r = @core.Replay::parse((
    #|{"out":{"id":1,"subscribe":{"topic":"a"},"keyed":true}}
    #|{"out":{"id":2,"call":"client.focus","params":{"end":false}}}
    #|{"in":{"id":2,"ok":null},"w":10}
    #|{"in":{"id":1,"value":1},"w":11}
  ))
  assert_eq(r.drop("\"end\":false"), 1)
  let c = r.client()
  let a = c.subscribe("a")
  assert_eq(r.deliver(), 1)
  assert_eq(a.value.map(fn(v) { v.stringify() }), Some("1"))
  assert_eq(r.left(), 0)
  assert_eq(r.unmade().length(), 0)
  assert_eq(r.drop("nothing like this"), 0)
}

///|
test "the bytes the run sent beside a call are the test's to give again" {
  let r = @core.Replay::parse(
    #|CORETRACE {"out":{"id":3,"call":"station.upload.part","params":{"name":"a.jpg","offset":0}},"w":10,"b":"ffd8ff"}
    #|CORETRACE {"in":{"id":3,"ok":{"have":3}},"w":20}
    #|CORETRACE {"out":{"id":4,"call":"station.upload.part","params":{"name":"b.pdf","offset":0}},"w":30}
    ,
  )
  assert_eq(r.sent_bytes("station.upload.part", "name", "a.jpg"), Some(b"\xff\xd8\xff"))
  assert_eq(r.sent_bytes("station.upload.part", "name", "b.pdf"), None)
  assert_eq(r.sent_bytes("chat.send", "name", "a.jpg"), None)
}

///|
/// The same run with its asks' wall clock: the message sent 2 s after the value came (the person thinking), answered
/// 50 ms after it went.
let paced : String =
  #|{"out":{"id":7,"subscribe":{"topic":"accounts"},"keyed":true},"w":900}
  #|{"in":{"id":7,"value":[]},"w":1000}
  #|{"out":{"id":9,"call":"chat.send","params":{"text":"hi"}},"w":3000}
  #|{"in":{"id":9,"ok":{"sent":true}},"w":3050}
  #|{"in":{"id":7,"value":[{"sub":"u1"}]},"w":3250}

///|
test "at the run's pace: a call's answer measured from its ask made again, the next from the answer" {
  let r = @core.Replay::parse(paced)
  let now : Ref[Double] = { val: 0.0 }
  r.clock(fn() { now.val })
  r.pace(@core.AsRun(1.0))
  let c = r.client()
  let s = c.subscribe("accounts")
  // the value: 100 ms after the subscription was made again
  assert_eq(r.next_due(), Some(100.0))
  assert_eq(r.deliver(now=99.0), 0)
  assert_eq(r.deliver(now=100.0), 1)
  assert_eq(s.value.unwrap().stringify(), "[]")
  // the answer waits for the message: whenever it is sent, nothing is due before
  assert_eq(r.next_due(), None)
  now.val = 500.0
  c.call("chat.send", params={ "text": "hi" }, on_done=fn(_) {  }) |> ignore
  // 50 ms after it was sent again, not 2 s after the value
  assert_eq(r.next_due(), Some(550.0))
  assert_eq(r.deliver(now=549.0), 0)
  assert_eq(r.deliver(now=550.0), 1)
  // the change: 200 ms after the answer was given
  assert_eq(r.next_due(), Some(750.0))
  assert_eq(r.deliver(now=750.0), 1)
  assert_eq(r.left(), 0)
}

///|
test "at the run's pace, an older trace (no wall clock on its asks): each message from the one before it" {
  let r = @core.Replay::parse(run)
  let now : Ref[Double] = { val: 0.0 }
  r.clock(fn() { now.val })
  r.pace(@core.AsRun(1.0))
  let c = r.client()
  c.subscribe("accounts") |> ignore
  // the first: at once
  assert_eq(r.deliver(now=0.0), 1)
  now.val = 40.0
  c.call("chat.send", params={ "text": "hi" }, on_done=fn(_) {  }) |> ignore
  // the answer: 200 ms after the value was given (the run's gap between them)
  assert_eq(r.next_due(), Some(200.0))
  assert_eq(r.deliver(now=200.0), 1)
  assert_eq(r.next_due(), Some(300.0))
}

///|
test "twice as slow, at once: the gaps scaled, or none" {
  let slow = @core.Replay::parse(paced)
  slow.clock(fn() { 0.0 })
  slow.pace(@core.AsRun(2.0))
  slow.client().subscribe("accounts") |> ignore
  assert_eq(slow.next_due(), Some(200.0))
  let fast = @core.Replay::parse(paced)
  fast.pace(@core.AtOnce)
  fast.client().subscribe("accounts") |> ignore
  assert_eq(fast.deliver(now=0.0), 1)
}

///|
/// A scripted run's steps on its trace (trace_steps): it typed 400 ms after the value came, then tapped send 600 ms
/// later (an upload going up meanwhile), the answer 50 ms after the send.
let stepped : String =
  #|CORETRACE {"out":{"id":7,"subscribe":{"topic":"accounts"},"keyed":true},"w":900}
  #|CORETRACE {"in":{"id":7,"value":[]},"w":1000}
  #|CORETRACE {"step":"until 发消息","w":1100}
  #|CORETRACE {"step":"type 你好","w":1400}
  #|CORETRACE {"step":"now tap icon:arrow-up","w":2000}
  #|CORETRACE {"out":{"id":9,"call":"chat.send","params":{"text":"你好"}},"w":2010}
  #|CORETRACE {"in":{"id":9,"ok":{"sent":true}},"w":2060}

///|
test "at the run's pace, its steps taken when it took them: each from the event before it taken again" {
  let r = @core.Replay::parse(stepped)
  let now : Ref[Double] = { val: 0.0 }
  r.clock(fn() { now.val })
  r.pace(@core.AsRun(1.0))
  let c = r.client()
  ignore(c.subscribe("accounts"))
  now.val = 100.0
  assert_eq(r.deliver(now=100.0), 1)
  // the waiting step 100 ms after the value; a step out of turn is none of the run's yet
  assert_eq(r.step_at("type 你好"), None)
  assert_eq(r.step_at("until 发消息"), Some(200.0))
  now.val = 200.0
  assert_true(r.step_taken("until 发消息"))
  // the typing 300 ms after it
  assert_eq(r.step_at("type 你好"), Some(500.0))
  now.val = 500.0
  assert_true(r.step_taken("type 你好"))
  // the tap 600 ms after the typing, whatever `now` the script put before it
  assert_eq(r.step_at("tap icon:arrow-up"), Some(1100.0))
  now.val = 1100.0
  assert_true(r.step_taken("tap icon:arrow-up"))
  now.val = 1110.0
  c.call("chat.send", params={ "text": "你好" }, on_done=fn(_) {  }) |> ignore
  assert_eq(r.next_due(), Some(1160.0))
  assert_eq(r.deliver(now=1160.0), 1)
  assert_eq(r.left(), 0)
  assert_eq(r.unmade().length(), 0)
  // at once: whenever the test takes it
  let q = @core.Replay::parse(stepped)
  q.pace(@core.AtOnce)
  assert_eq(q.step_at("until 发消息"), Some(-@double.infinity))
}

///|
test "step_of: the line as the drive took it" {
  assert_eq(step_of("now noticed 出错 · "), Some("noticed 出错 ·"))
  assert_eq(step_of("tap =保存"), Some("tap 保存"))
  assert_eq(step_of("wait 1500"), None)
}

///|
/// What came in a run, its gaps under a frame's.
let close_in : String =
  #|{"out":{"id":7,"subscribe":{"topic":"accounts"},"keyed":true},"w":900}
  #|{"in":{"id":7,"value":[]},"w":1000}
  #|{"in":{"id":7,"value":[{"sub":"u1"}]},"w":1001}
  #|{"in":{"id":7,"value":[{"sub":"u2"}]},"w":1017}
  #|{"in":{"id":7,"value":[{"sub":"u3"}]},"w":1018}
  #|{"in":{"id":7,"value":[{"sub":"u4"}]},"w":1034}

///|
test "at the run's pace, given a frame at a time: each due by the run's gaps, not from the frame it was given in" {
  let r = @core.Replay::parse(close_in)
  r.clock(fn() { 0.0 })
  r.pace(@core.AsRun(1.0))
  r.client().subscribe("accounts") |> ignore
  // frames at 0, 16, 32…: the value at 100, then two a frame, as they came
  assert_eq(r.deliver(now=96.0), 0)
  assert_eq(r.deliver(now=112.0), 2)
  assert_eq(r.deliver(now=128.0), 2)
  assert_eq(r.deliver(now=144.0), 1)
  assert_eq(r.left(), 0)
}

///|
/// A step that acts said twice by the run: as its line began, and as its input went to the host three frames on (a
/// message come meanwhile).
let acted : String =
  #|CORETRACE {"out":{"id":7,"subscribe":{"topic":"accounts"},"keyed":true},"w":900}
  #|CORETRACE {"in":{"id":7,"value":[]},"w":1000}
  #|CORETRACE {"step":"back","w":1100}
  #|CORETRACE {"in":{"id":7,"value":[{"sub":"u1"}]},"w":1120}
  #|CORETRACE {"step":"back","acted":true,"w":1148}
  #|CORETRACE {"in":{"id":7,"value":[{"sub":"u2"}]},"w":1200}

///|
test "at the run's pace, a step that acts taken when its input went, what came before that before it" {
  let r = @core.Replay::parse(acted)
  let now : Ref[Double] = { val: 0.0 }
  r.clock(fn() { now.val })
  r.pace(@core.AsRun(1.0))
  ignore(r.client().subscribe("accounts"))
  assert_eq(r.deliver(now=100.0), 1)
  // the message come as the line began is not held for the step: 120 ms after the value
  assert_eq(r.deliver(now=220.0), 1)
  // the step when its input went: 28 ms after that message, not when its line began
  assert_eq(r.step_at("back"), Some(248.0))
  now.val = 248.0
  assert_true(r.step_taken("back"))
  assert_eq(r.next_due(), Some(300.0))
  assert_eq(r.deliver(now=300.0), 1)
  assert_eq(r.left(), 0)
}

///|
test "frame_period: the run's frames as its host's lines space them, two lines a frame" {
  let r = @core.Replay::parse(
    #|{"info":{"view":1,"at":[0]},"w":1000.0}
    #|{"info":{"view":1,"at":[0]},"w":1000.3}
    #|{"info":{"view":1,"at":[16]},"w":1016.5}
    #|{"info":{"view":1,"at":[16]},"w":1016.8}
    #|{"info":{"view":1,"at":[33]},"w":1033.25}
    #|{"info":{"view":1,"at":[900]},"w":1900.0}
    ,
  )
  // (the pause before the last left out)
  assert_eq(r.frame_period(), Some(16.625))
  assert_eq(@core.Replay::parse(paced).frame_period(), None)
}
