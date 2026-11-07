///|
test "scrolling near the start asks for the previous page once and retries a failed request" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  for _ in 0..<40 {
    if !named(calls, "chat.older").is_empty() {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  assert_eq(named(calls, "chat.older").length(), 1)
  // More frames and scrolling while the same page is pending must not ask for it again.
  t.frame()
  t.wheel(195.0, 400.0, -200.0)
  assert_eq(named(calls, "chat.older").length(), 1)
  (named(calls, "chat.older")[0].done)(Err({ "message": "offline" }))
  t.draw()
  assert_eq(named(calls, "chat.older").length(), 2)
}

///|
test "a window short of the end asks for its next page again when the cursor changes" {
  let calls : Array[Made] = []
  let cursor = @signals.signal(100.0, same=fn(a, b) { a == b })
  let t = fake_core(calls, over=fn(name, topic) {
    if name != "chat" {
      return topic
    }
    match topic.value {
      Some(Object(value)) => {
        let value = value.copy()
        value["more"] = false
        value["newer"] = true
        value["lastEntry"] = Json::number(cursor.get())
        { ..topic, value: Some(Json::object(value)), version: topic.version + cursor.get().to_int() }
      }
      _ => topic
    }
  })
  assert_eq(named(calls, "chat.newer").length(), 1)
  t.frame()
  assert_eq(named(calls, "chat.newer").length(), 1)
  cursor.set(101.0)
  t.draw()
  assert_eq(named(calls, "chat.newer").length(), 2)
}
