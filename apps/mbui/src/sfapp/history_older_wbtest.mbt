// An agent's history read up toward its top: the page before is asked for as the reader comes within a height of it,
// and comes in above what is read, which stays where it is; the page before that is asked for only as the reader goes
// on up to within a height of that one's top, not one after another to its start.

///|
/// Pages `from` to 4 of an agent's history (its words, 30 to a page), more before them while `from` is past the first.
fn older_history(from : Int) -> Json {
  let items : Array[Json] = []
  for p in from..<5 {
    for j in 0..<30 {
      let words = "第 \{p} 页第 \{j} 条"
      items.push({
        "key": Json::string("p\{p}-\{j}"),
        "entries": [Json::number((p * 30 + j).to_double()), Json::number((p * 30 + j).to_double())],
        "body": { "kind": "text", "content": { "text": Json::string(words), "line": Json::string(words), "subagent": false } },
      })
    }
  }
  { "items": Json::array(items), "live": [], "usage": [], "edge": "从 10/19 08:12 开始", "empty": false, "loaded": true, "more": from > 0 }
}

///|
test "an agent's history read up toward its top asks for the page before once, what was read staying where it is" {
  new_run()
  let base = fixture("chat")
  let from = @signals.signal(4)
  let asked : Array[Int] = []
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "history" {
        { value: Some(older_history(from.get())), error: None, version: 1 }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
    // (asked: the page comes as the test says, below)
    call: fn(name, params, done) {
      if name == "history.older" {
        asked.push(from.get())
        done(Ok(Json::null()))
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("第 4 页第 29 条") is Some(_))
  assert_eq(asked.length(), 0)
  // pulled down slowly, a little at a time (not flung), until it comes within a height of its top and the page before
  // is asked for
  let in_sight = fn(j : Int) {
    match t.find("第 4 页第 \{j} 条") {
      Some((_, y)) => y > 200.0 && y < 700.0
      None => false
    }
  }
  for _ in 0..<60 {
    if asked.length() > 0 {
      break
    }
    t.drag(195.0, 300.0, 195.0, 420.0, steps=40)
  }
  assert_eq(asked, [4])
  let seen = match Array::makei(30, fn(j) { j }).search_by(in_sight) {
    Some(j) => "第 4 页第 \{j} 条"
    None => fail("none of the page in sight")
  }
  // at rest where the finger let it go on to; then the page before comes in above: asked once, what was read where it
  // was, not the top of the page come in
  t.run_for(history_fling_ms)
  let was = t.find(seen).map(fn(at) { at.1 })
  from.set(3)
  t.run_for(@ui.move_most_ms)
  assert_eq(asked, [4])
  assert_eq(t.find(seen).map(fn(at) { at.1 }), was)
  assert_true(t.find("第 3 页第 0 条") is None)
  // on up: the page come in over what was read, its last under its first; the page before that not asked for till the
  // reader is within a height of this one's top
  for _ in 0..<60 {
    if t.find("第 3 页第 29 条") is Some((_, y)) && y > 200.0 {
      break
    }
    t.drag(195.0, 300.0, 195.0, 420.0, steps=40)
  }
  t.run_for(history_fling_ms)
  match (t.find("第 3 页第 29 条"), t.find("第 4 页第 0 条")) {
    (Some((_, last)), Some((_, first))) => assert_true(last < first, msg="\{last} over \{first}")
    _ => fail("the page come in is not over what was read")
  }
  // (the page before that: not asked for till the reader is within a height of this one's top)
  assert_eq(asked, [4])
  for _ in 0..<60 {
    if asked.length() > 1 {
      break
    }
    t.drag(195.0, 300.0, 195.0, 420.0, steps=40)
  }
  assert_eq(asked, [4, 3])
}

///|
test "an agent's history opened at an entry before what is loaded asks for its page, once: not the one before that as it comes" {
  new_run()
  let base = fixture("chat")
  let from = @signals.signal(4)
  let asked : Array[Int] = []
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "history" {
        { value: Some(older_history(from.get())), error: None, version: 1 }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
    // (answered at once, as a page held on the device is)
    call: fn(name, params, done) {
      if name == "history.older" {
        asked.push(from.get())
        from.set(from.get() - 1)
        done(Ok(Json::null()))
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  // (entry 115: the page before's 26th item, 25 rows under that page's top)
  app.nav.push(History(r, "s-c1", Some(115)))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("第 3 页第 25 条") is Some(_))
  assert_eq(asked, [4])
}

///|
test "an agent's history asks for the page before again only once the core no longer says its read failed" {
  new_run()
  let base = fixture("chat")
  let older = @signals.signal("")
  let asked = Ref(0)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "history" {
        let h = match older_history(4) {
          Object(m) => {
            let m = m.copy()
            if older.get() != "" {
              m["older"] = Json::string(older.get())
              m["edge"] = Json::string("读取更早的执行历史失败：busy，稍后重试")
            }
            Json::object(m)
          }
          j => j
        }
        { value: Some(h), error: None, version: 1 }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
    call: fn(name, params, done) {
      if name == "history.older" {
        asked.val = asked.val + 1
        older.set("failed")
        done(Err("busy"))
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  for _ in 0..<60 {
    if asked.val > 0 {
      break
    }
    t.drag(195.0, 300.0, 195.0, 420.0, steps=40)
  }
  assert_eq(asked.val, 1)
  t.run_for(history_fling_ms)
  // on up to its top, the core saying why there: not asked again meanwhile, however it is moved
  for _ in 0..<30 {
    if t.find("读取更早的执行历史失败：busy，稍后重试") is Some((_, y)) && y > 0.0 {
      break
    }
    t.drag(195.0, 300.0, 195.0, 420.0, steps=40)
    t.run_for(history_fling_ms)
  }
  assert_eq(asked.val, 1)
  assert_true(t.find("读取更早的执行历史失败：busy，稍后重试") is Some(_))
  // its while up: asked again
  older.set("")
  t.run_for(@ui.move_most_ms)
  assert_eq(asked.val, 2)
}

///|
test "an agent's history whose first read failed says why over its bones" {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "history" {
        {
          value: Some({ "items": [], "live": [], "usage": [], "edge": "正在读取执行历史", "empty": true, "loaded": false, "failed": "station 正忙" }),
          error: None,
          version: 1,
        }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("station 正忙") is Some(_))
}
