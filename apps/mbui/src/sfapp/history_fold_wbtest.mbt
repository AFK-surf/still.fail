// An agent's history on 小屏 holding a message longer than its fold: the list opens on it cut to its lines, the button
// under it saying how many more there are, the app laying it out once (it laid it out whole, cut it, laid it out whole
// again, for ever: the app froze as the history opened, 0.1.7935).

///|
/// A page of an agent's work, a message to it of `lines` lines among it.
fn fold_history(lines : Int) -> Json {
  let items : Array[Json] = []
  let long = StringBuilder()
  for q in 0..<lines {
    long.write_string("第 \{q} 行，一段很长的话，反复出现用来撑出很多行的文字。\n")
  }
  for j in 0..<30 {
    let body : Json = if j == 25 {
      {
        "kind": "received",
        "content": {
          "tasks": [],
          "messages": [{ "key": "m\{j}", "from": { "name": "林", "bound": false }, "text": Json::string(long.to_string()) }],
        },
      }
    } else {
      { "kind": "group", "content": { "summary": "读了文件 \{j}", "title": "读取", "failures": 0, "pending": 0, "rows": [] } }
    }
    items.push({ "key": Json::string("i\{j}"), "entries": [Json::number(j.to_double()), Json::number(j.to_double())], "body": body })
  }
  { "items": Json::array(items), "live": [], "usage": [], "edge": "从 10/19 08:12 开始", "empty": false, "loaded": true, "more": false }
}

///|
test "an agent's history on 小屏 opens on a message longer than its fold, cut to its lines" {
  for lines in [8, 60] {
    new_run()
    let base = fixture("chat")
    let history = fold_history(lines)
    let src : Source = {
      ..base,
      topic_read: fn(name, params) {
        if name == "history" {
          { value: Some(history), error: None, version: 1 }
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
    assert_true(t.find("第 0 行") is Some(_), msg="\{lines}")
    assert_true(t.find("展开 · 还有 ") is Some(_), msg="\{lines}")
  }
}

///|
/// A page of an agent's work: groups of three calls, each call's output long, and every third a message longer than
/// its fold.
fn pressed_history() -> Json {
  let items : Array[Json] = []
  let long = StringBuilder()
  for q in 0..<30 {
    long.write_string("第 \{q} 行，一段很长的话，反复出现用来撑出很多行的文字。\n")
  }
  let step = fn(j : Int, n : Int) -> Json {
    let out = StringBuilder()
    for q in 0..<12 {
      out.write_string("结果 \{j}-\{n} 第 \{q} 行\n")
    }
    {
      "kind": "step",
      "content": {
        "name": "Read",
        "hint": Json::string("文件 \{j}-\{n}.mbt"),
        "meta": "",
        "failed": false,
        "call": "{\"file_path\": \"/a.mbt\"}",
        "result": Json::string(out.to_string()),
        "entries": [3, 4],
        "brief": false,
      },
    }
  }
  for j in 0..<30 {
    let body : Json = if j % 3 == 1 {
      {
        "kind": "received",
        "content": {
          "tasks": [],
          "messages": [{ "key": "m\{j}", "from": { "name": "林", "bound": false }, "text": Json::string("消息 \{j}\n" + long.to_string()) }],
        },
      }
    } else {
      {
        "kind": "group",
        "content": {
          "summary": Json::string("读了文件 \{j}"),
          "title": "读取",
          "failures": 0,
          "pending": 0,
          "rows": [step(j, 0), step(j, 1), step(j, 2)],
        },
      }
    }
    items.push({ "key": Json::string("i\{j}"), "entries": [Json::number(j.to_double()), Json::number(j.to_double())], "body": body })
  }
  { "items": Json::array(items), "live": [], "usage": [], "edge": "从 10/19 08:12 开始", "empty": false, "loaded": true, "more": false }
}

///|
/// The history of `pressed_history` open on 小屏.
fn pressed_tester() -> @ui.Tester {
  new_run()
  let base = fixture("chat")
  let history = pressed_history()
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "history" {
        { value: Some(history), error: None, version: 1 }
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
  t
}

///|
/// Where node `id` (a semantics node's) is drawn down the window now, none where it is not.
fn pressed_y(t : @ui.Tester, id : Int) -> Double? {
  t.all(Button).search_by(fn(n) { n.id == id }).map(fn(i) { t.all(Button)[i].rect.1 })
}

///|
test "what is pressed in an agent's history to open or shut stays where it was pressed, all the way" {
  // (the history at its foot, part way up, and at its top)
  for ups in [0, 6, 40] {
    let t = pressed_tester()
    for _ in 0..<ups {
      t.wheel(195.0, 400.0, -400.0)
      t.run_for(@ui.move_most_ms)
    }
    // every one in sight that opens, opened, then shut: in the same place on its way and once it is there
    let shut = t
      .all(Button, expanded=false)
      .filter(fn(n) { n.rect.1 > 120.0 && n.rect.1 + n.rect.3 < 760.0 })
      .map(fn(n) { n.id })
    assert_true(shut.length() > 1, msg="\{ups}: \{shut.length()} in sight")
    for id in shut {
      guard pressed_y(t, id) is Some(was) else { continue }
      for turn in ["open", "shut"] {
        guard t.all(Button).search_by(fn(n) { n.id == id }) is Some(i) else { fail("\{ups} \{id}: gone before \{turn}") }
        let (x, y, w, h) = t.all(Button)[i].rect
        t.tap(x + w / 2.0, y + h / 2.0)
        for k in [1.0, 2.0, 3.0, 4.0, 5.0] {
          t.run_for(@ui.move_most_ms / 4.0)
          match pressed_y(t, id) {
            Some(now) =>
              assert_true((now - was).abs() < 0.5, msg="\{ups} \{id} \{turn} at \{k}/4 of a move: \{was} -> \{now}")
            None => fail("\{ups} \{id} \{turn}: gone at \{k}/4")
          }
        }
      }
    }
  }
}
