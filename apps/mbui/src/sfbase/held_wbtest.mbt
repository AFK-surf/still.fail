///|
test "what a page read is let go of as it ends, once, and nothing it never read" {
  held_reset()
  let left : Array[String] = []
  let made = made_source()
  let src : Source = {
    ..made,
    leave: fn(name, params, __reason) {
      if __reason is TopicLeave::Owned(__stop) { __stop(); return }
      left.push(name + " " + (if params.get("job").unwrap_or(Json::string("")) is String(s) { Some(s) } else { None }).unwrap()) },
    release: fn(name, params) { left.push(name + " " + (if params.get("job").unwrap_or(Json::string("")) is String(s) { Some(s) } else { None }).unwrap()) },
  }
  let log = fn(job : String) -> Map[String, Json] {
    { "station": Json::string("s"), "job": Json::string(job), "lines": Json::number(1.0) }
  }
  // read each frame: held once
  held_build()
  ignore(hold(src, jobs_scope("s"), "jobLog", log("a")).get().snapshot())
  ignore(hold(src, jobs_scope("s"), "jobLog", log("a")).get().snapshot())
  ignore(hold(src, jobs_scope("s"), "jobLog", log("b")).get().snapshot())
  // the same topic read for another thing too
  ignore(hold(src, chat_scope("s", "c"), "jobLog", log("a")).get().snapshot())
  // what is read in the build it ends in is still shown: kept
  let_go(src, jobs_scope("s"))
  assert_eq(left, [])
  ignore(hold(src, jobs_scope("s"), "jobLog", log("a")).get().snapshot())
  ignore(hold(src, jobs_scope("s"), "jobLog", log("b")).get().snapshot())
  held_build()
  let_go(src, chat_scope("s", "x"))
  assert_eq(left, [])
  let_go(src, jobs_scope("s"))
  assert_eq(left, ["jobLog b"])
  // The other scope still holds a until it too leaves.
  let_go(src, chat_scope("s", "c"))
  left.sort()
  assert_eq(left, ["jobLog a", "jobLog b"])
  assert_eq(left.length(), 2)
  let_go(src, jobs_scope("s"))
  assert_eq(left.length(), 2)
}

///|
test "the same scope and topic read a changed source" {
  held_reset()
  let first = made_source(topic=fn(_, _) { Some({ "value": "first" }) })
  let second = made_source(topic=fn(_, _) { Some({ "value": "second" }) })
  held_build()
  assert_eq(text(hold(first, "scope", "topic", {}).get().value, "value"), "first")
  assert_eq(text(hold(second, "scope", "topic", {}).get().value, "value"), "second")
  held_build()
  let_go(second, "scope")
  held_reset()
}
