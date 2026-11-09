// An agent's history holding a message from a person in another chat, its label longer than its line: what it says
// goes on in the next line whole, each part as wide as its words; it was laid out in one line, every part squeezed
// (收到来…, its name in two lines, 的…, desktop 0.1.7973).

///|
/// A page of an agent's work: a message to it from `name` in the chat `chat`.
fn label_history(name : String, chat : String) -> Json {
  let body : Json = {
    "kind": "received",
    "content": {
      "tasks": [],
      "messages": [
        {
          "key": "m0",
          "from": { "name": Json::string(name), "bound": false },
          "place": { "name": Json::string(chat), "surface": "chat", "session": "s-c2" },
          "text": "用户反馈执行历史还是一直骨架屏",
        },
      ],
    },
  }
  {
    "items": [{ "key": "i0", "entries": [0, 0], "body": body }],
    "live": [],
    "usage": [],
    "edge": "从 10/19 08:12 开始",
    "empty": false,
    "loaded": true,
    "more": false,
  }
}

///|
test "a message's label longer than its line goes on in the next, each part whole" {
  new_run()
  let base = fixture("chat")
  let history = label_history("Zijian Zuo", "安卓执行历史一直骨架屏，滚动加载也有很多问题")
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
  let before = t.rect_of("收到来自").unwrap()
  let who = t.rect_of("Zijian Zuo").unwrap()
  let after = t.rect_of("的消息").unwrap()
  let place = t.rect_of("安卓执行历史").unwrap()
  // (each in one line, 18 high: the name and the place were in two, 36)
  for r in [before, who, after, place] {
    assert_eq(r.3, 18.0)
  }
  // (the words around the name whole: cut they were 36.5 and 28.4 wide, whole 58.5 and 45.5)
  assert_eq(before.2, 58.5)
  assert_eq(after.2, 45.5)
  // (the three in the first line, side by side; the place in the next)
  assert_eq(who.1, before.1)
  assert_eq(after.1, before.1)
  assert_true(before.0 + before.2 <= who.0 && who.0 + who.2 <= after.0)
  assert_eq(place.1, before.1 + 18.0)
}
