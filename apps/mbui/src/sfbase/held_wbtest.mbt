///|
/// A made-up core whose leaves are said in `left` (each topic's name and job, as `jobLog a`).
fn held_test_src(left : Array[String]) -> Source {
  let made = made_source()
  { ..made, leave: fn(name, params) { left.push(name + " " + params.get("job").or(Json::string("")).as_string().unwrap()) } }
}

///|
fn held_log(job : String) -> Map[String, Json] {
  { "station": Json::string("s"), "job": Json::string(job), "lines": Json::number(1.0) }
}

///|
test "what a holder read is left as it is let go, once, and nothing it never read" {
  held_reset()
  let left : Array[String] = []
  let src = held_test_src(left)
  ignore(hold_named(src, jobs_scope("s"), "jobLog", held_log("a")))
  ignore(hold_named(src, jobs_scope("s"), "jobLog", held_log("a")))
  ignore(hold_named(src, jobs_scope("s"), "jobLog", held_log("b")))
  let_go_named(src, chat_scope("s", "x"))
  assert_eq(left, [])
  let_go_named(src, jobs_scope("s"))
  left.sort()
  assert_eq(left, ["jobLog a", "jobLog b"])
  // let go again: nothing more
  let_go_named(src, jobs_scope("s"))
  assert_eq(left.length(), 2)
}

///|
test "a topic two hold is left only as the last of them is let go" {
  held_reset()
  let left : Array[String] = []
  let src = held_test_src(left)
  ignore(hold_named(src, jobs_scope("s"), "jobLog", held_log("a")))
  ignore(hold_named(src, chat_scope("s", "c"), "jobLog", held_log("a")))
  let_go_named(src, jobs_scope("s"))
  assert_eq(left, [])
  let_go_named(src, chat_scope("s", "c"))
  assert_eq(left, ["jobLog a"])
}

///|
test "a holder let go twice, as its node goes and by its name, takes away its own hold once, not another's" {
  held_reset()
  let left : Array[String] = []
  let src = held_test_src(left)
  let h = Holder::new("node")
  ignore(h.hold(src, "jobLog", held_log("a")))
  ignore(hold_named(src, chat_scope("s", "c"), "jobLog", held_log("a")))
  h.let_go()
  h.let_go()
  assert_eq(left, [])
  let_go_named(src, chat_scope("s", "c"))
  assert_eq(left, ["jobLog a"])
}

///|
test "one holder let go and another holding the same in that change: nothing left, nothing read again for it" {
  held_reset()
  let left : Array[String] = []
  let read = Ref(0)
  let made = held_test_src(left)
  let src = { ..made, topic: fn(name, params) { read.val += 1; (made.topic)(name, params) } }
  ignore(hold_named(src, history_scope("s", "k"), "jobLog", held_log("a")))
  let before = read.val
  @signals.start_batch()
  let_go_named(src, history_scope("s", "k"))
  ignore(hold_named(src, history_scope("s", "k") + "\u{1}again", "jobLog", held_log("a")))
  @signals.end_batch()
  assert_eq(left, [])
  assert_eq(read.val, before + 1)
  // that one let go in a change of its own: left as it is over
  let_go_named(src, history_scope("s", "k") + "\u{1}again")
  assert_eq(left, ["jobLog a"])
}
