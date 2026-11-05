///|
test "a fixture chat reply changes its topic without notifying unchanged preferences" {
  new_run()
  let src = fixture("chat")
  let prefs : Array[Int] = []
  let chat : Array[Int] = []
  let stop_prefs = @signals.effect(fn() { prefs.push((src.topic)("prefs", {}).version) })
  let stop_chat = @signals.effect(fn() {
    chat.push((src.topic)("chat", { "station": "st1", "session": "s-c1" }).version)
  })
  @sffixture.fix_now(fn() { fix_chat("s-c1").working = 10.0 })
  stop_prefs()
  stop_chat()
  assert_eq(prefs.length(), 1, msg="unchanged preferences must not notify the frame")
  assert_eq(chat.length(), 2)
  assert_true(chat[1] > chat[0])
}

///|
test "a fixture preference snapshot stays as it was when a nested map changes" {
  new_run()
  let src = fixture("chat")
  let seen : Array[@sfbase.Topic] = []
  let stop = @signals.effect(fn() { seen.push((src.topic)("prefs", {})) })
  let change : Json = { "sidebars": { "ws1\nchat": { "width": 280 } } }
  (src.call)("prefs.set", change, fn(_) { })
  (src.call)("prefs.set", change, fn(_) { })
  stop()
  assert_eq(seen.length(), 2, msg="the repeated value is not another topic change")
  assert_true(seen[1].version > seen[0].version)
  assert_true(field(seen[0].value, "sidebars") == Some(Json::object({})))
  assert_true(field(seen[1].value, "sidebars") == field(Some(change), "sidebars"))
}
