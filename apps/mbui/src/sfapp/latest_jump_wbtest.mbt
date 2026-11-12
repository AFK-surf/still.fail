// A chat shown short of its end, newer messages not brought in (the core's `newer`; sfpages' chat_list.mbt to_latest):
// the way to its end says how many new messages wait there, and pressed asks the core for the chat's latest page
// (chat.latest), not a glide over what is in the list.

///|
test "a chat short of its end: its way to the end says how many new messages wait (3 条新消息); pressed, the core is asked for its latest page" {
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    guard name == "chat" && tp.value is Some(Object(m)) else { return tp }
    let o = m.copy()
    o["newer"] = Json::boolean(true)
    o["thread"] = { "id": 7, "unread": 3 }
    { ..tp, value: Some(Json::object(o)) }
  })
  t.run_for(@ui.move_most_ms)
  guard t.find("3 条新消息") is Some((x, y)) else { fail("\{Repr(t.words().map(fn(w) { w.0 }))}") }
  assert_eq(named(calls, "chat.latest").length(), 0)
  t.tap(x, y)
  t.draw()
  let made = named(calls, "chat.latest")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "station"), "ws1/st1")
  assert_eq(number(Some(made[0].params), "thread"), 7.0)
}

///|
test "a chat at its end with nothing newer: no count of new messages on the way to its end" {
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    guard name == "chat" && tp.value is Some(Object(m)) else { return tp }
    let o = m.copy()
    o["thread"] = { "id": 7, "unread": 3 }
    { ..tp, value: Some(Json::object(o)) }
  })
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("3 条新消息") is None)
}

///|
test "at the end of a window short of the chat's end, the page after is asked for (chat.newer) once, not again each frame" {
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    guard name == "chat" && tp.value is Some(Object(m)) else { return tp }
    let o = m.copy()
    o["newer"] = Json::boolean(true)
    { ..tp, value: Some(Json::object(o)) }
  })
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  let made = named(calls, "chat.newer")
  assert_eq(made.length(), 1)
  assert_eq(number(Some(made[0].params), "thread"), 7.0)
  // its answer failed: asked again
  (made[0].done)(Err({ "message": "连不上" }))
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.newer").length(), 2)
}

///|
test "the page before asked for as the reader nears the chat's top (chat.older), once; its answer failed, asked again" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.run_for(@ui.move_most_ms)
  t.move_to(195.0, 400.0)
  for _ in 0..<6 {
    t.wheel(195.0, 400.0, -900.0)
    t.run_for(@ui.move_most_ms)
  }
  let asked = named(calls, "chat.older")
  assert_eq(asked.length(), 1)
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
  (asked[0].done)(Err({ "message": "连不上" }))
  t.wheel(195.0, 400.0, 300.0)
  t.run_for(@ui.move_most_ms)
  t.wheel(195.0, 400.0, -900.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.older").length(), 2)
}
