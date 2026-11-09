// An agent's history on 小屏 holding a message longer than its fold: the list opens on it cut to its lines, the button
// under it saying how many more there are, the app laying it out once (it laid it out whole, cut it, laid it out whole
// again, for ever: the app froze as the history opened, 0.1.7935).

///|
/// A page of an agent's work, a message to it of `lines` lines among it.
fn fold_history(lines : Int) -> Json {
  let items : Array[Json] = []
  let long = StringBuilder::new()
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
