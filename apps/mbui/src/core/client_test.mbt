// The client over recorded messages: the smoke run's (scripts/core.sh smoke: accounts, auth.begin; the login URL's
// state and challenge replaced) and deltas as the core sends them.

///|
fn recorder() -> (@core.Client, Array[Json]) {
  let sent : Array[Json] = []
  let c = @core.Client::new(fn(s) { sent.push(@json.parse(s) catch { _ => Json::null() }) })
  (c, sent)
}

///|
test "subscribe asks once, keyed, and takes the first value" {
  let (c, sent) = recorder()
  let s = c.subscribe("accounts")
  let again = c.subscribe("accounts")
  assert_true(physical_equal(s, again))
  assert_eq(sent.length(), 1)
  let want : Json = { "id": 1, "subscribe": { "topic": "accounts" }, "keyed": true }
  assert_eq(sent[0].stringify(), want.stringify())
  assert_true(s.value is None)
  // recorded: the smoke run's first message
  assert_true(c.receive("{\"id\":1,\"value\":[]}"))
  assert_eq(s.value.unwrap().stringify(), "[]")
  assert_eq(s.version, 1)
}

///|
test "params make another subscription" {
  let (c, sent) = recorder()
  let a = c.subscribe("threads", params={ "station": "ws/a" })
  let b = c.subscribe("threads", params={ "station": "ws/b" })
  assert_true(a.id != b.id)
  assert_eq(
    sent[1].stringify(),
    ({ "id": 2, "subscribe": { "topic": "threads", "station": "ws/b" }, "keyed": true } : Json).stringify(),
  )
}

///|
test "a call's answer goes to its on_done" {
  let (c, sent) = recorder()
  let got : Array[String] = []
  let params : Json = {
    "redirect_uri": "stillfail://auth/callback",
    "return_to": "/",
  }
  let id = c.call("auth.begin", params~, on_done=fn(r) {
    match r {
      Ok(Object(m)) =>
        match m.get("url") {
          Some(String(u)) => got.push(u)
          _ => ()
        }
      _ => got.push("error")
    }
  })
  assert_eq(id, 1)
  assert_eq(
    sent[0].stringify(),
    ({ "id": 1, "call": "auth.begin", "params": params } : Json).stringify(),
  )
  // recorded (state and challenge replaced)
  c.receive(
    "{\"id\":1,\"ok\":{\"url\":\"https://app.still.fail/v1/auth/google/start?state=S&code_challenge=C&code_challenge_method=S256&redirect_uri=stillfail%3A%2F%2Fauth%2Fcallback&name=still.fail\"}}",
  )
  |> ignore
  assert_eq(got.length(), 1)
  assert_true(got[0].has_prefix("https://app.still.fail/v1/auth/google/start?"))
  // answered once
  c.receive("{\"id\":1,\"ok\":null}") |> ignore
  assert_eq(got.length(), 1)
}

///|
test "a call's error" {
  let (c, _) = recorder()
  let got : Array[Json] = []
  c.call("auth.complete", params={ "query": "x" }, on_done=fn(r) {
    match r {
      Err(e) => got.push(e)
      Ok(_) => ()
    }
  })
  |> ignore
  c.receive(
    "{\"id\":1,\"error\":{\"code\":\"bad_request\",\"message\":\"no state\",\"status\":400}}",
  )
  |> ignore
  assert_eq(
    got[0].stringify(),
    "{\"code\":\"bad_request\",\"message\":\"no state\",\"status\":400}",
  )
}

///|
test "deltas apply to the value; versions count the messages" {
  let (c, _) = recorder()
  let s = c.subscribe("threads", params={ "station": "ws/s" })
  let v0 = c.version
  c.receive("{\"id\":1,\"delta\":[{\"path\":[],\"set\":1}]}") |> ignore
  // a delta before any value is not applied
  assert_true(s.value is None)
  assert_eq(s.version, 0)
  c.receive(
    "{\"id\":1,\"value\":[{\"id\":\"a\",\"t\":\"A\"},{\"id\":\"b\",\"t\":\"B\"}]}",
  )
  |> ignore
  let first = s.value.unwrap()
  c.receive(
    "{\"id\":1,\"delta\":[{\"path\":[],\"key\":[\"id\"],\"move\":\"b\",\"before\":\"a\"},{\"path\":[],\"key\":[\"id\"],\"patch\":\"a\",\"ops\":[{\"path\":[\"t\"],\"set\":\"A2\"}]}]}",
  )
  |> ignore
  assert_eq(
    s.value.unwrap().stringify(),
    "[{\"id\":\"b\",\"t\":\"B\"},{\"id\":\"a\",\"t\":\"A2\"}]",
  )
  // the value a view held before is as it was
  assert_eq(first.stringify(), "[{\"id\":\"a\",\"t\":\"A\"},{\"id\":\"b\",\"t\":\"B\"}]")
  assert_eq(s.version, 2)
  assert_eq(c.version, v0 + 2)
}

///|
test "an error clears the value until the next one" {
  let (c, _) = recorder()
  let s = c.subscribe("workspace", params={ "workspace": "w" })
  c.receive("{\"id\":1,\"value\":{\"a\":1}}") |> ignore
  c.receive("{\"id\":1,\"error\":{\"code\":\"offline\",\"message\":\"no network\"}}")
  |> ignore
  assert_true(s.value is None)
  assert_true(s.error is Some(_))
  c.receive("{\"id\":1,\"delta\":[{\"path\":[\"a\"],\"set\":2}]}") |> ignore
  assert_true(s.value is None)
  c.receive("{\"id\":1,\"value\":{\"a\":3}}") |> ignore
  assert_eq(s.value.unwrap().stringify(), "{\"a\":3}")
  assert_true(s.error is None)
  assert_eq(s.version, 3)
}

///|
test "a fatal fails the calls in flight; restarted asks every subscription again" {
  let (c, sent) = recorder()
  let s = c.subscribe("accounts")
  c.receive("{\"id\":1,\"value\":[]}") |> ignore
  let errs : Array[Json] = []
  c.call("auth.begin", on_done=fn(r) {
    match r {
      Err(e) => errs.push(e)
      Ok(_) => ()
    }
  })
  |> ignore
  c.receive("{\"fatal\":\"boom\"}") |> ignore
  assert_eq(c.fatal, Some("boom"))
  assert_eq(errs.length(), 1)
  // (in the app's words, as StillFailCore.kt fails them; the core's own reason kept in `fatal`)
  assert_eq(errs[0].stringify(), "{\"code\":\"core_restarted\",\"message\":\"" + restarted_text.val + "\"}")
  sent.clear()
  c.restarted()
  assert_eq(c.fatal, None)
  assert_eq(sent.length(), 1)
  assert_eq(
    sent[0].stringify(),
    ({ "id": 1, "subscribe": { "topic": "accounts" }, "keyed": true } : Json).stringify(),
  )
  // the old value stays until the new core's
  assert_eq(s.value.unwrap().stringify(), "[]")
}

///|
test "unsubscribe tells the core and forgets the subscription" {
  let (c, sent) = recorder()
  let s = c.subscribe("accounts")
  c.unsubscribe(s)
  assert_eq(sent[1].stringify(), ({ "id": 1, "unsubscribe": true } : Json).stringify())
  c.receive("{\"id\":1,\"value\":[1]}") |> ignore
  assert_true(s.value is None)
  let again = c.subscribe("accounts")
  assert_eq(again.id, 2)
}

///|
test "leaving an unasked topic does not start it" {
  let (c, sent) = recorder()
  let summary : Map[String, Json] = { "station": "ws/s", "summary": true }
  let full : Map[String, Json] = { "station": "ws/s" }
  let held = c.subscribe("chatJobs", params=summary)
  c.unsubscribe_topic("chatJobs", params=full)
  assert_eq(sent.length(), 1, msg="an unopened jobs page is not asked just to leave it")
  c.unsubscribe_topic("chatJobs", params=summary)
  assert_eq(sent.length(), 2)
  assert_eq(sent[1].stringify(), ({ "id": 1, "unsubscribe": true } : Json).stringify())
  c.unsubscribe_topic("chatJobs", params=summary)
  assert_eq(sent.length(), 2)
  assert_true(c.subscribe("chatJobs", params=summary).id != held.id)
}

///|
test "what is not a message is let be" {
  let (c, _) = recorder()
  assert_false(c.receive("not json"))
  assert_true(c.receive("{\"id\":99,\"ok\":1}"))
  assert_true(c.receive("[1,2]"))
  assert_eq(c.version, 0)
}

///|
test "query_of: a callback URL's query" {
  assert_eq(
    @core.query_of("stillfail://auth/callback?code=a&state=b#x"),
    "code=a&state=b",
  )
  assert_eq(@core.query_of("stillfail://auth/callback?code=a"), "code=a")
  assert_eq(@core.query_of("stillfail://auth/callback"), "")
}

///|
test "a call whose answer has bytes beside it gets them, a plain call doesn't" {
  let (c, _) = recorder()
  let got : Array[(String, Int)] = []
  c.call_bytes(
    "media.image",
    params={ "station": "s", "book": "b", "ref": "r" },
    on_done=fn(r) {
      match r {
        Ok((j, Some(b))) => got.push((j.stringify(), b.length()))
        _ => got.push(("none", 0))
      }
    },
  )
  |> ignore
  c.receive_json(
    @json.parse("{\"id\":1,\"ok\":{\"type\":\"image/png\",\"size\":4}}"),
    bytes=Some(b"\x89PNG"),
  )
  assert_eq(got, [("{\"type\":\"image/png\",\"size\":4}", 4)])
  // the bytes are the message's only
  let plain : Array[Bool] = []
  c.call_bytes("media.image", on_done=fn(r) {
    plain.push(r is Ok((_, None)))
  })
  |> ignore
  c.receive_json(@json.parse("{\"id\":2,\"ok\":{}}"))
  assert_eq(plain, [true])
}

///|
test "a streamed call: each value before its answer, with the bytes beside it; cancelled, nothing more" {
  let (c, sent) = recorder()
  let heard : Array[String] = []
  let done : Array[String] = []
  let id = c.stream("station.preview", on_value=fn(v, b) {
    heard.push(v.stringify() + " " + b.map(fn(x) { x.length() }).unwrap_or(-1).to_string())
  }, on_done=fn(r) { done.push(if r is Ok(_) { "ok" } else { "err" }) })
  c.receive_json({ "id": Json::number(id.to_double()), "value": { "head": { "status": 200 } } })
  c.receive_json({ "id": Json::number(id.to_double()), "value": { "chunk": true } }, bytes=Some(b"abc"))
  c.receive_json({ "id": Json::number(id.to_double()), "ok": Json::null() })
  assert_eq(heard, ["{\"head\":{\"status\":200}} -1", "{\"chunk\":true} 3"])
  assert_eq(done, ["ok"])
  let id2 = c.stream("station.preview", on_value=fn(_, _) { heard.push("late") })
  c.cancel(id2)
  assert_eq(sent[sent.length() - 1].stringify(), "{\"id\":\{id2},\"cancel\":true}")
  c.receive_json({ "id": Json::number(id2.to_double()), "value": { "chunk": true } })
  assert_eq(heard.length(), 2)
}

///|
test "what is asked of the core is awaited until answered or first read" {
  let sent : Array[String] = []
  let c = Client::new(fn(s) { sent.push(s) })
  let waits : Map[Int, String] = {}
  let n = Ref::new(0)
  c.track(
    fn(what) {
      n.val += 1
      waits[n.val] = what
      n.val
    },
    fn(t) { waits.remove(t) },
  )
  let s = c.subscribe("overview", params={ "station": Json::string("st1") })
  let id = c.call("chat.send", params=Json::object({}))
  assert_eq(waits.length(), 2)
  // the subscription's first value: no longer awaited
  assert_true(c.receive("{\"id\":\{s.id},\"value\":{\"a\":1}}"))
  assert_eq(waits.values().collect(), ["core: chat.send (call \{id})"])
  // a delta later awaits nothing
  assert_true(c.receive("{\"id\":\{id},\"ok\":true}"))
  assert_eq(waits.length(), 0)
  // a stream cancelled, a subscription ended before its value
  let st = c.stream("station.preview", on_value=fn(_, _) {  })
  let s2 = c.subscribe("jobs", params={ "station": Json::string("st1") })
  assert_eq(waits.length(), 2)
  c.cancel(st)
  c.unsubscribe(s2)
  assert_eq(waits.length(), 0)
  // a fatal ends every call's wait; the core started again is asked again, and awaited
  ignore(c.call("x"))
  assert_true(c.receive("{\"fatal\":\"gone\"}"))
  assert_eq(waits.length(), 0)
  c.restarted()
  assert_eq(waits.length(), 1)
}

///|
test "a core started anew is told again where the app's attention is (client.focus, as told last)" {
  let sent : Array[String] = []
  let c = Client::new(fn(m) { sent.push(m) })
  c.call("client.focus", params={ "visible": true, "focused": true, "workspace": "ws1" }) |> ignore
  sent.clear()
  c.restarted()
  assert_eq(sent.length(), 1)
  assert_true(sent[0].contains("client.focus"))
  assert_true(sent[0].contains("\"visible\":true"))
}

///|
test "a subscription's changes are pushed: what read it in a computed follows each message for it, and its end" {
  let (c, _) = recorder()
  let s = c.subscribe("accounts")
  let worked = Ref(0)
  let seen = @signals.computed(fn(_) {
    worked.val += 1
    // (as an app's source reads a topic: core_topic)
    let read = c.subscribe("accounts").followed()
    match read.value {
      Some(Array(a)) => a.length()
      _ => -1
    }
  })
  assert_eq(seen.get(), -1)
  assert_eq(seen.get(), -1)
  assert_eq(worked.val, 1)
  // the core's first value: pushed on, worked out again once
  assert_true(c.receive("{\"id\":1,\"value\":[]}"))
  assert_eq(seen.get(), 0)
  assert_eq(seen.get(), 0)
  assert_eq(worked.val, 2)
  // a delta
  assert_true(c.receive("{\"id\":1,\"delta\":[{\"path\":[],\"append\":[1]}]}"))
  assert_eq(seen.get(), 1)
  assert_eq(worked.val, 3)
  // let go: what read it reads it anew, from the subscription asked again
  c.unsubscribe(s)
  assert_eq(seen.get(), -1)
  assert_eq(worked.val, 4)
  assert_true(c.receive("{\"id\":2,\"value\":[7,8]}"))
  assert_eq(seen.get(), 2)
}

///|
test "a quiet call's values and an unread call's answer may be taken as they come; the rest may not" {
  let (c, _) = recorder()
  c.quiet("screen.view", fn(v) { v is Object(o) && o.keys().all(fn(k) { k == "frame" }) })
  c.unread("screen.ack")
  let values : Array[String] = []
  let view = c.stream("screen.view", on_value=fn(v, _) { values.push(v.stringify()) })
  let ack = c.call("screen.ack")
  let other = c.call("prefs.set")
  let said = fn(m : Json) {
    guard m is Object(o) else { return false }
    c.call_said(o)
  }
  // a frame alone: quiet; a state: what a frame reads
  assert_true(said({ "id": view, "value": { "frame": { "ts": 1 } } }))
  assert_false(said({ "id": view, "value": { "state": {} } }))
  assert_false(said({ "id": view, "value": { "frame": { "ts": 1 }, "config": {} } }))
  // its answer is read
  assert_false(said({ "id": view, "ok": {} }))
  // the ack's answer nobody reads; another call's is read
  assert_true(said({ "id": ack, "ok": {} }))
  assert_true(said({ "id": ack, "error": {} }))
  assert_false(said({ "id": other, "ok": {} }))
  // answered: nothing more of it is said
  c.receive_json({ "id": ack, "ok": {} })
  assert_false(said({ "id": ack, "ok": {} }))
  c.receive_json({ "id": view, "value": { "frame": { "ts": 2 } } })
  assert_eq(values, ["{\"frame\":{\"ts\":2}}"])
  // over: its values no longer quiet
  c.receive_json({ "id": view, "ok": {} })
  assert_false(said({ "id": view, "value": { "frame": { "ts": 3 } } }))
}
