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
    topic_read: fn(_, _) {
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
    (if v is Number(n, ..) { Some(n) } else { None }).unwrap_or(0.0)
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
    topic_read: fn(_, params) { { value: params.get("chat"), error: None, version: 1 } },
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
      seen.val = made.read(src, "rows", fn(_) {
        worked.val += 1
        let n = (if src.topic("counted", {}).get().value.unwrap() is Number(n, ..) { Some(n) } else { None }).unwrap_or(0.0)
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
  let inner : @sfbase.Derived[Double] = @sfbase.Derived::new("counted", fn(v, _) { (if v is Number(n, ..) { Some(n) } else { None }).unwrap_or(0.0) })
  let outer : @sfbase.Kept[String] = @sfbase.Kept::new()
  let worked = Ref(0)
  let seen = Ref("")
  let t = @ui.Tester::new(fn(_) {
    // (only the outer one read here: the topic is read by the inner one, in the outer's getter)
    seen.val = outer.read(src, "line", fn(_) {
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
    topic_read: fn(name, params) {
      if name == "chat" {
        changes.get() |> ignore
        { value: Some(value.val), error: None, version: version.val }
      } else {
        base.topic(name, params).get().snapshot()
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

///|
test "a chat's unrelated metadata leaves its messages and rows as they were; an unread line or message change does not" {
  let original : Json = {
    "title": "原名",
    "thread": { "id": 1 },
    "messages": Json::array([said(1, "第一句"), said(2, "第二句")]),
    "agents": [],
    "people": [],
  }
  let value = Ref(original)
  let version = Ref(1)
  let changes = @signals.signal(1)
  let src = pushed_source(value, version, changes)
  let r : ChatRef = { station: "ws1/st1", session: "metadata-only", title: "", station_name: "" }
  let seen_view : Ref[ChatView?] = Ref(None)
  let seen_list : Ref[Array[Entry]] = Ref([])
  let t = @ui.Tester::new(fn(_) {
    let (v, entries, _) = view_of_chat(src, r)
    seen_view.val = v
    seen_list.val = entries
  })
  t.draw()
  let old_messages = seen_view.val.unwrap().messages
  let old_list = seen_list.val
  let fields = match value.val {
    Object(m) => m.copy()
    _ => fail("chat is not an object")
  }
  fields["title"] = Json::string("新名")
  value.val = Json::object(fields)
  version.val = 2
  changes.set(2)
  t.draw()
  assert_eq(seen_view.val.unwrap().title, "新名")
  assert_true(physical_equal(seen_view.val.unwrap().messages, old_messages))
  assert_true(physical_equal(seen_list.val, old_list))

  let fields = fields.copy()
  fields["unreadLine"] = Json::number(2.0)
  value.val = Json::object(fields)
  version.val = 3
  changes.set(3)
  t.draw()
  assert_false(physical_equal(seen_list.val, old_list))
  assert_true(seen_list.val.iter().any(fn(e) { e is Line }))

  let fields = fields.copy()
  fields["messages"] = Json::array([said(1, "第一句"), said(2, "改过")])
  value.val = Json::object(fields)
  version.val = 4
  changes.set(4)
  t.draw()
  assert_eq(seen_view.val.unwrap().messages[1].text, "改过")
  assert_true(seen_list.val.iter().any(fn(e) { match e { Said(m) => m.text == "改过"; _ => false } }))

  let fields = fields.copy()
  fields["agents"] = Json::array([{ "status": "running", "session": { "key": "agent-1" } }])
  value.val = Json::object(fields)
  version.val = 5
  changes.set(5)
  t.draw()
  assert_true(seen_list.val.iter().any(fn(e) { match e { Working(a) => a.key == "agent-1"; _ => false } }))

  let fields = fields.copy()
  fields["agents"] = Json::array([])
  fields["outbox"] = Json::array([{ "id": "pending-1", "text": "正发送" }])
  value.val = Json::object(fields)
  version.val = 6
  changes.set(6)
  t.draw()
  assert_true(seen_list.val.iter().any(fn(e) { match e { Out(o) => o.text == "正发送"; _ => false } }))
}

///|
test "a message appended after unchanged history keeps its old entries and rebuilds the live tail" {
  let messages = [said(1, "第一句"), said(2, "第二句")]
  let fields : Map[String, Json] = {
    "thread": { "id": 1 },
    "messages": Json::array(messages),
    "unreadLine": 3,
    "outbox": [{ "id": "old", "text": "原发送" }],
    "stateText": "原状态",
    "agents": [{ "status": "running", "session": { "key": "agent" } }],
  }
  let value = Ref(Json::object(fields))
  let version = Ref(1)
  let changes = @signals.signal(1)
  let src = pushed_source(value, version, changes)
  let r : ChatRef = { station: "ws1/st1", session: "append-entries", title: "", station_name: "" }
  let entries : Ref[Array[Entry]] = Ref([])
  let t = @ui.Tester::new(fn(_) { entries.val = view_of_chat(src, r).1 })
  t.draw()
  let before = entries.val
  assert_eq(before.map(fn(e) { e.id() }), ["top", "m:t1", "m:t2", "o:old", "state", "act:agent", "foot"])

  let message = match said(3, "第三句") {
    Object(m) => m.copy()
    _ => fail("message is not an object")
  }
  message["elsewhere"] = Json::array([{ "key": "forward", "text": "转发" }])
  messages.push(Json::object(message))
  let next = fields.copy()
  next["outbox"] = Json::array([{ "id": "new", "text": "新发送" }])
  next["stateText"] = Json::string("新状态")
  value.val = Json::object(next)
  version.val = 2
  changes.set(2)
  t.draw()
  assert_eq(
    entries.val.map(fn(e) { e.id() }),
    ["top", "m:t1", "m:t2", "line", "m:t3", "s:forward", "o:new", "state", "act:agent", "foot"],
  )
  assert_true(physical_equal(entries.val[1], before[1]))
  assert_true(physical_equal(entries.val[2], before[2]))
  assert_eq(before.map(fn(e) { e.id() }), ["top", "m:t1", "m:t2", "o:old", "state", "act:agent", "foot"])
  assert_true(entries.val.iter().any(fn(e) { match e { State(a, _, _) => a == "新状态"; _ => false } }))
}

///|
test "messages replaced or reordered in the same source array keep the unread line and do not change old rows" {
  let messages = [said(1, "第一句"), said(2, "第二句"), said(3, "第三句")]
  let initial : Json = {
    "thread": { "id": 1 },
    "messages": Json::array(messages),
    "unreadLine": 2,
  }
  let value = Ref(initial)
  let version = Ref(1)
  let changes = @signals.signal(1)
  let src = pushed_source(value, version, changes)
  let r : ChatRef = { station: "ws1/st1", session: "changed-history", title: "", station_name: "" }
  let entries : Ref[Array[Entry]] = Ref([])
  let t = @ui.Tester::new(fn(_) { entries.val = view_of_chat(src, r).1 })
  t.draw()
  let original = entries.val
  assert_eq(original.map(fn(e) { e.id() }), ["top", "m:t1", "line", "m:t2", "m:t3", "foot"])
  messages[1] = said(2, "改过的第二句")
  version.val = 2
  changes.set(2)
  t.draw()
  let replaced = entries.val
  assert_eq(replaced.map(fn(e) { e.id() }), ["top", "m:t1", "line", "m:t2", "m:t3", "foot"])
  assert_true(replaced.iter().any(fn(e) { match e { Said(m) => m.text == "改过的第二句"; _ => false } }))
  assert_true(original.iter().any(fn(e) { match e { Said(m) => m.text == "第二句"; _ => false } }))
  let first = messages[0]
  let second = messages[1]
  messages[0] = messages[2]
  messages[1] = first
  messages[2] = second
  version.val = 3
  changes.set(3)
  t.draw()
  assert_eq(entries.val.map(fn(e) { e.id() }), ["top", "m:t3", "m:t1", "line", "m:t2", "foot"])
  assert_eq(replaced.map(fn(e) { e.id() }), ["top", "m:t1", "line", "m:t2", "m:t3", "foot"])
  assert_true(replaced.iter().any(fn(e) { match e { Said(m) => m.text == "改过的第二句"; _ => false } }))
}

///|
/// What made_again made of `before` (each made the text of its words), then of `now` from that, and how many of `now`
/// it made anew.
fn made_again_of(before : Array[Json], now : Array[Json]) -> (Array[(Json, String)], Array[(Json, String)], Int) {
  let made = Ref(0)
  let make = fn(j : Json) {
    made.val += 1
    text(Some(j), "text")
  }
  let key = fn(j : Json) { text(Some(j), "ts") }
  let was = @sfbase.made_again(before, [], key, make)
  made.val = 0
  let then = @sfbase.made_again(now, was, key, make)
  (was, then, made.val)
}

///|
test "made again: one come at the end, one changed, one gone, one moved back, a page come before: only what is new made" {
  let ms = Array::makei(50, fn(i) { said(i + 1, "第 \{i + 1} 句") })
  let same = fn(was : Array[(Json, String)], then : Array[(Json, String)], w : Int, t : Int) {
    physical_equal(was[w].1, then[t].1)
  }
  // one come at the end
  let more = ms.copy()
  more.push(said(51, "新的一句"))
  let (was, then, made) = made_again_of(ms, more)
  assert_eq(made, 1)
  assert_true(same(was, then, 0, 0) && same(was, then, 49, 49))
  assert_eq(then[50].1, "新的一句")
  // one changed in the middle
  let changed = ms.mapi(fn(i, m) { if i == 20 { said(21, "改过") } else { m } })
  let (was, then, made) = made_again_of(ms, changed)
  assert_eq(made, 1)
  assert_true(same(was, then, 19, 19) && same(was, then, 21, 21))
  assert_eq(then[20].1, "改过")
  // one gone from the middle
  let gone = ms.filter(fn(m) { !physical_equal(m, ms[30]) })
  let (was, then, made) = made_again_of(ms, gone)
  assert_eq(made, 0)
  assert_true(same(was, then, 29, 29) && same(was, then, 31, 30))
  // the last moved to the front
  let moved = [ms[49]]
  for i in 0..<49 {
    moved.push(ms[i])
  }
  let (was, then, made) = made_again_of(ms, moved)
  assert_eq(made, 0)
  assert_true(same(was, then, 49, 0) && same(was, then, 0, 1) && same(was, then, 48, 49))
  // a page come before them, all of it new
  let older = Array::makei(20, fn(i) { said(-i, "更早的 \{i}") })
  let page = older.copy()
  page.push_iter(ms.iter())
  let (was, then, made) = made_again_of(ms, page)
  assert_eq(made, 20)
  assert_true(same(was, then, 0, 20) && same(was, then, 49, 69))
}

///|
test "a chat's page with nothing changed goes over none of its rows again; a message come, its rows made again" {
  new_run()
  let base = fixture("chat")
  let messages = Array::makei(30, fn(i) { said(i + 1, "第 \{i + 1} 句") })
  let title = Ref("整理发布清单")
  let clear_ask = Ref(false)
  let changes = @signals.signal(1)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "chat" && params.get("session") == Some(Json::string("s-c1")) {
        let version = changes.get()
        let chat : Json = {
          "title": Json::string(title.val),
          "thread": { "id": 1 },
          "messages": Json::array(messages),
          "agents": [],
          "people": [],
          "asks": if clear_ask.val { [{ "seq": 1 }] } else { [] },
          "askClear": Json::boolean(clear_ask.val),
        }
        { value: Some(chat), error: None, version }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let rd = @sfbase.reading_of("ws1/st1\u{1}s-c1")
  let rows = rd.motion_keys
  assert_true(rows.length() > 30)
  t.frame()
  t.frame()
  assert_true(physical_equal(rd.motion_keys, rows))
  // Unrelated metadata changes, but its message rows and their names do not need to be made again.
  title.val = "发布清单"
  changes.set(2)
  t.frame()
  assert_true(physical_equal(rd.motion_keys, rows))
  assert_true(t.find("发布清单") is Some(_))
  // The bell changes the foot's room even though the message entries themselves are unchanged.
  let foot = t.row(rd.motion_keys.length() - 1).unwrap().3
  clear_ask.val = true
  changes.set(3)
  t.frame()
  assert_false(physical_equal(rd.motion_keys, rows))
  t.run_for(@ui.row_size_ms / 2.0)
  let foot_half = t.row(rd.motion_keys.length() - 1).unwrap().3
  assert_true(foot_half > foot, msg="foot \{foot}, halfway \{foot_half}")
  let after_ask = rd.motion_keys
  // one more said: its rows made again, the new one among them once it has come in
  messages.push(said(31, "新的一句"))
  changes.set(4)
  t.frame()
  assert_false(physical_equal(rd.motion_keys, after_ask))
  t.run_for(@sf.enter_ms)
  assert_true(rd.motion_keys.iter().any(fn(k) { k.has_suffix("m:t31") }), msg=Repr(rd.motion_keys).to_string())
}

///|
test "a chat keeps its rows when scrolled and renamed, then shows a new message at the end" {
  new_run()
  let base = fixture("chat")
  let messages = Array::makei(30, fn(i) { said(i + 1, "第 \{i + 1} 句") })
  let title = Ref("整理发布清单")
  let changes = @signals.signal(1)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "chat" && params.get("session") == Some(Json::string("s-c1")) {
        let version = changes.get()
        let chat : Json = {
          "title": Json::string(title.val),
          "thread": { "id": 1 },
          "messages": Json::array(messages),
          "agents": [],
          "people": [],
        }
        { value: Some(chat), error: None, version }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let rd = @sfbase.reading_of("ws1/st1\u{1}s-c1")
  let rows = rd.motion_keys
  assert_true(t.at_end())
  t.scroll_to(4)
  t.frame()
  assert_false(t.at_end())
  let (first, _) = t.visible()
  assert_true(first >= 0 && first < 15, msg="first visible row \{first}")
  assert_true(physical_equal(rd.motion_keys, rows))
  title.val = "发布清单"
  changes.set(2)
  t.frame()
  assert_true(t.find("发布清单") is Some(_))
  assert_false(t.at_end())
  assert_eq(t.visible().0, first)
  assert_true(physical_equal(rd.motion_keys, rows))
  messages.push(said(31, "新的一句"))
  changes.set(3)
  t.frame()
  t.run_for(@sf.enter_ms)
  assert_false(t.at_end())
  assert_eq(t.visible().0, first)
  assert_true(rd.motion_keys.iter().any(fn(k) { k.has_suffix("m:t31") }))
  t.scroll_to_end()
  t.frame()
  assert_true(t.at_end())
  assert_true(t.find("新的一句") is Some(_))
}
