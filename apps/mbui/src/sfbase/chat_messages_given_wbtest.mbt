///|
/// A chat's value as a made-up core gives it, whole: its messages, the one of seq 1 `followed` or not.
fn given_chat(followed : Bool) -> Json {
  let one : Map[String, Json] = { "seq": Json::number(1.0), "ts": Json::string("a"), "text": Json::string("一") }
  if followed {
    one["followed"] = Json::boolean(true)
  }
  let two : Map[String, Json] = {
    "seq": Json::number(2.0),
    "ts": Json::string("b"),
    "text": Json::string("二"),
    "joined": Json::boolean(true),
  }
  Json::object({ "messages": Json::array([Json::object(one), Json::object(two)]) })
}

///|
test "a made-up core's chat given whole again: a message set otherwise is its row's version one more, one the same is not" {
  let was = ChatMessages::of_value(Some(given_chat(false)))
  let (one, two) = (was.row(0).version, was.row(1).version)
  let sign = shown_sign(Said(was.row(0)))
  // (the message before the one joined to it followed now: what its row shows (its time line gone) changed)
  let now = ChatMessages::of_value(Some(given_chat(true)), was~)
  assert_true(now.row(0).version != one, msg="the followed message's row told it changed")
  assert_true(shown_sign(Said(now.row(0))) != sign, msg="its sign another: its room worked out again")
  assert_eq(now.row(1).version, two)
}
