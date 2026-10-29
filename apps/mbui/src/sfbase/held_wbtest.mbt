///|
test "what a page read is let go of as it ends, once, and nothing it never read" {
  held_reset()
  let left : Array[String] = []
  let made = made_source()
  let src : Source = {
    ..made,
    leave: fn(name, params) { left.push(name + " " + params.get("job").or(Json::string("")).as_string().unwrap()) },
  }
  let log = fn(job : String) -> Map[String, Json] {
    { "station": Json::string("s"), "job": Json::string(job), "lines": Json::number(1.0) }
  }
  // read each frame: held once
  held_build(1)
  ignore(hold(src, jobs_scope("s"), "jobLog", log("a")))
  ignore(hold(src, jobs_scope("s"), "jobLog", log("a")))
  ignore(hold(src, jobs_scope("s"), "jobLog", log("b")))
  // the same topic read for another thing too
  ignore(hold(src, chat_scope("s", "c"), "jobLog", log("a")))
  // what is read in the build it ends in is still shown: kept
  let_go(src, jobs_scope("s"))
  assert_eq(left, [])
  ignore(hold(src, jobs_scope("s"), "jobLog", log("a")))
  ignore(hold(src, jobs_scope("s"), "jobLog", log("b")))
  held_build(2)
  let_go(src, chat_scope("s", "x"))
  assert_eq(left, [])
  let_go(src, jobs_scope("s"))
  left.sort()
  assert_eq(left, ["jobLog a", "jobLog b"])
  // left for all: the other does not leave it again
  let_go(src, chat_scope("s", "c"))
  assert_eq(left.length(), 2)
  let_go(src, jobs_scope("s"))
  assert_eq(left.length(), 2)
}
