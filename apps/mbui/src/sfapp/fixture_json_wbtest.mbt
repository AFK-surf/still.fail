///|
test "a screen's JSON: its topics by name and params, its calls answered, its pages opened" {
  new_run()
  let src = fixture_json(
    #|{"workspace": "ws1",
    #| "open": [{"page": "settings"}],
    #| "topics": [{"topic": {"topic": "notify"}, "value": {"on": true}},
    #|            {"topic": {"topic": "chat", "station": "ws1/st1", "session": "s-c1"}, "value": {"title": "整理发布清单"}}],
    #| "calls": [{"call": "draft.get", "params": {"key": "b"}, "ok": "B"}, {"call": "draft.get", "params": {"key": "a"}, "ok": "A"}]}
    ,
  )
  assert_eq((src.topic)("notify", {}).value, Some({ "on": true }))
  let chat : Map[String, Json] = { "station": Json::string("ws1/st1"), "session": Json::string("s-c1") }
  assert_eq(text((src.topic)("chat", chat).value, "title"), "整理发布清单")
  // another chat's: none (a page that waits for it, as over a core that has not said it yet)
  chat["session"] = Json::string("s-c2")
  assert_true((src.topic)("chat", chat).value is None)
  let got : Array[Result[Json, Json]] = []
  (src.call)("draft.get", { "key": "a" }, fn(r) { got.push(r) })
  // another's params: the first answer by its name
  (src.call)("draft.get", { "key": "c" }, fn(r) { got.push(r) })
  (src.call)("drive.read", {}, fn(r) { got.push(r) })
  assert_eq(got[0], Ok(Json::string("A")))
  assert_eq(got[1], Ok(Json::string("B")))
  assert_true(got[2] is Err(_))
  assert_true(app.nav.top() is Settings)
}
