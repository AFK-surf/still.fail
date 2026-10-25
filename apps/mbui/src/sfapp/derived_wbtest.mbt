// What the pages work out of a topic (sfbase derived.mbt: alien-signals' computed, mbui/signals), following the core's
// changes from the core on (src/core Sub.changes): once for each change, however many read it and however often, a
// computed of a computed too; and from what it made last, what did not change kept as it was made (the user,
// 2026-10-26: 「不应该有个跟 preact signals 一样的机制来保证只计算一次吗」「实现可以抄一下 alien-signals」「让这套 signals 机制从
// core 到 ui 能完整连上」).

///|
/// A source whose topic `counted` is `value` at version `version`, its changes said as the core client says a
/// subscription's: a signal its readers follow (`changes`), set by the test as the value changes.
fn pushed_source(value : Ref[Json], version : Ref[Int], changes : @signals.Signal[Int]) -> Source {
  {
    ..fixture("home"),
    topic: fn(_, _) {
      changes.get() |> ignore
      { value: Some(value.val), error: None, version: version.val }
    },
  }
}

///|
test "a topic's value is worked out once for each change the core pushes, however often the frames read it" {
  let value = Ref(Json::number(1.0))
  let version = Ref(1)
  let changes = @signals.signal(1)
  let src = pushed_source(value, version, changes)
  let worked = Ref(0)
  let made : @sfbase.Derived[Double] = @sfbase.Derived::new("counted", fn(v, _) {
    worked.val += 1
    v.as_number().unwrap_or(0.0)
  })
  let seen = Ref(0.0)
  let t = @ui.Tester::new(fn(_) {
    // (read three times a frame: a page, its side panel and the frame round them)
    for _ in 0..<3 {
      seen.val = made.read(src, { "chat": Json::string("c1") }).0.unwrap_or(-1.0)
    }
  })
  t.draw()
  t.draw()
  t.draw()
  assert_eq(seen.val, 1.0)
  assert_eq(worked.val, 1)
  // the core says it changed: worked out again, once
  value.val = Json::number(2.0)
  version.val = 2
  changes.set(2)
  t.draw()
  t.draw()
  assert_eq(seen.val, 2.0)
  assert_eq(worked.val, 2)
}

///|
test "what is worked out of a topic another chat reads is that chat's own" {
  let src : Source = {
    ..fixture("home"),
    topic: fn(_, params) { { value: params.get("chat"), error: None, version: 1 } },
  }
  let made : @sfbase.Derived[String] = @sfbase.Derived::new("named", fn(v, _) {
    match v {
      String(s) => s
      _ => ""
    }
  })
  let seen : Array[String] = []
  let t = @ui.Tester::new(fn(_) {
    seen.clear()
    for chat in ["c1", "c2"] {
      seen.push(made.read(src, { "chat": Json::string(chat) }).0.unwrap_or(""))
    }
  })
  t.draw()
  assert_eq(seen, ["c1", "c2"])
}

///|
test "what is worked out of a topic and a signal of the page's is worked out again only as one of them changes" {
  let value = Ref(Json::number(1.0))
  let version = Ref(1)
  let changes = @signals.signal(1)
  let src = pushed_source(value, version, changes)
  let only_io = @signals.signal(false, same=fn(a, b) { a == b })
  let made : @sfbase.Kept[String] = @sfbase.Kept::new()
  let worked = Ref(0)
  let seen = Ref("")
  let t = @ui.Tester::new(fn(_) {
    for _ in 0..<3 {
      seen.val = made.read("rows", fn(_) {
        worked.val += 1
        let n = (src.topic)("counted", {}).value.unwrap().as_number().unwrap_or(0.0)
        "\{n.to_int()} \{only_io.get()}"
      })
    }
  })
  t.draw()
  t.draw()
  assert_eq(seen.val, "1 false")
  assert_eq(worked.val, 1)
  // the page's own: once
  only_io.set(true)
  t.draw()
  t.draw()
  assert_eq(seen.val, "1 true")
  assert_eq(worked.val, 2)
  // the topic's: once
  value.val = Json::number(2.0)
  version.val = 2
  changes.set(2)
  t.draw()
  t.draw()
  assert_eq(seen.val, "2 true")
  assert_eq(worked.val, 3)
}

///|
test "a computed of what was worked out of a topic follows the topic, the topic itself not read where it is read" {
  let value = Ref(Json::number(1.0))
  let version = Ref(1)
  let changes = @signals.signal(1)
  let src = pushed_source(value, version, changes)
  let inner : @sfbase.Derived[Double] = @sfbase.Derived::new("counted", fn(v, _) { v.as_number().unwrap_or(0.0) })
  let outer : @sfbase.Kept[String] = @sfbase.Kept::new()
  let worked = Ref(0)
  let seen = Ref("")
  let t = @ui.Tester::new(fn(_) {
    // (only the outer one read here: the topic is read by the inner one, in the outer's getter)
    seen.val = outer.read("line", fn(_) {
      worked.val += 1
      "seen \{inner.read(src, {}).0.unwrap_or(0.0).to_int()}"
    })
  })
  t.draw()
  t.draw()
  assert_eq(seen.val, "seen 1")
  assert_eq(worked.val, 1)
  value.val = Json::number(2.0)
  version.val = 2
  changes.set(2)
  t.draw()
  assert_eq(seen.val, "seen 2")
  assert_eq(worked.val, 2)
}

///|
/// A message of a chat's topic as the core gives it.
fn said(seq : Int, words : String) -> Json {
  {
    "seq": Json::number(seq.to_double()),
    "thread": 1,
    "ts": Json::string("t\{seq}"),
    "authorKind": "person",
    "author": "林",
    "text": Json::string(words),
  }
}

///|
test "a chat's messages the core's change did not touch are kept as they were read; only what came is read" {
  let first = said(1, "第一句")
  let second = said(2, "第二句")
  let chat = fn(messages : Array[Json]) -> Json {
    { "title": "整理发布清单", "thread": { "id": 1 }, "messages": Json::array(messages), "agents": [], "people": [] }
  }
  let value = Ref(chat([first, second]))
  let version = Ref(1)
  let changes = @signals.signal(1)
  let base = fixture("home")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "chat" {
        changes.get() |> ignore
        { value: Some(value.val), error: None, version: version.val }
      } else {
        (base.topic)(name, params)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-x", title: "", station_name: "" }
  let seen : Ref[Array[Message]] = Ref([])
  let t = @ui.Tester::new(fn(_) {
    seen.val = match view_of_chat(src, r).0 {
      Some(v) => v.messages
      None => []
    }
  })
  t.draw()
  let was = seen.val
  assert_eq(was.length(), 2)
  // one more said, as a delta brings it: the two before the same JSON (src/core delta.mbt keeps them)
  value.val = chat([first, second, said(3, "第三句")])
  version.val = 2
  changes.set(2)
  t.draw()
  assert_eq(seen.val.length(), 3)
  assert_true(physical_equal(seen.val[0], was[0]))
  assert_true(physical_equal(seen.val[1], was[1]))
  assert_eq(seen.val[2].text, "第三句")
  // the second changed: that one read again, the first kept
  value.val = chat([first, said(2, "第二句，改过"), said(3, "第三句")])
  version.val = 3
  changes.set(3)
  let before = seen.val
  t.draw()
  assert_true(physical_equal(seen.val[0], before[0]))
  assert_false(physical_equal(seen.val[1], before[1]))
  assert_eq(seen.val[1].text, "第二句，改过")
}
