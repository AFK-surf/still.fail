// What an agent of the chat said in Slack or Feishu rather than here, or a person's message there it was given
// (sfpages' message.mbt sent_elsewhere, elsewhere_route): drawn as their message, where it went or came from after the
// name, 发送失败 in red where sending it failed; the place pressed opens it.

///|
/// The fixture's chat with `e` (the core's Message `elsewhere`) after its last message.
fn elsewhere_chat(e : Json) -> @ui.Tester {
  let calls : Array[Made] = []
  fake_core(calls, over=fn(name, tp) {
    guard name == "chat" && tp.value is Some(Object(m)) else { return tp }
    let all = items(tp.value, "messages").copy()
    let last = all.length() - 1
    match all[last] {
      Object(lm) => {
        let w = lm.copy()
        w["elsewhere"] = Json::array([e])
        all[last] = Json::object(w)
      }
      _ => ()
    }
    let o = m.copy()
    o["messages"] = Json::array(all)
    o["askClear"] = Json::boolean(false)
    { ..tp, value: Some(Json::object(o)) }
  })
}

///|
fn elsewhere_said(failed? : Bool = false, received? : Bool = false, url? : String = "") -> Json {
  {
    "key": "e9",
    "text": "安装包签名已经核对完了",
    "place": { "name": "星火#发布", "surface": "slack:T1", "url": url },
    "failed": failed,
    "received": received,
    "by": @sffixture.by_agent("anthropic", "claude", "s-c1"),
  }
}

///|
test "what an agent said in a Slack thread instead of the chat: its words as its message, 发送到 and the thread after its name" {
  let t = elsewhere_chat(elsewhere_said())
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("安装包签名已经核对完了") is Some(_))
  let (_, wy) = t.find("安装包签名已经核对完了").unwrap()
  let (rx, ry) = t.find("发送到").unwrap()
  let (px, py) = t.find("星火#发布").unwrap()
  // (its route on its head's line, over its words; the place after 发送到)
  assert_true(ry < wy && (py - ry).abs() < 4.0 && px > rx, msg="\{Repr((rx, ry))} \{Repr((px, py))} \{wy}")
  assert_true(t.find("发送失败") is None)
  assert_true(t.find("来自") is None)
}

///|
test "what failed to go to Slack says 发送失败 after where it was for" {
  let t = elsewhere_chat(elsewhere_said(failed=true))
  t.run_for(@ui.move_most_ms)
  guard t.find("星火#发布") is Some((px, py)) else { fail("no place: \{Repr(t.words().map(fn(w) { w.0 }))}") }
  guard t.find("发送失败") is Some((fx, fy)) else { fail("no 发送失败: \{Repr(t.words().map(fn(w) { w.0 }))}") }
  assert_true(fx > px && (fy - py).abs() < 4.0, msg="\{Repr((px, py))} \{Repr((fx, fy))}")
}

///|
test "a person's message in the Slack thread the chat was given says 来自 and the thread, not 发送到" {
  let t = elsewhere_chat(elsewhere_said(received=true))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("来自") is Some(_))
  assert_true(t.find("发送到") is None)
  assert_true(t.find("星火#发布") is Some(_))
}

///|
test "the thread named after 发送到 pressed opens it where it has its link; without one, pressing it opens nothing" {
  let url = "https://acme.slack.com/archives/C1/p1"
  let t = elsewhere_chat(elsewhere_said(url~))
  t.run_for(@ui.move_most_ms)
  guard t.find("星火#发布") is Some(_) else { fail("no place: \{Repr(t.words().map(fn(w) { w.0 }))}") }
  t.tap_text("星火#发布")
  t.draw()
  assert_true(t.opened().contains(url), msg="\{Repr(t.opened())}")
  let t = elsewhere_chat(elsewhere_said())
  t.run_for(@ui.move_most_ms)
  t.tap_text("星火#发布")
  t.draw()
  assert_true(t.opened().is_empty(), msg="\{Repr(t.opened())}")
}

///|
test "its time pressed says when it was, and pressed again how long ago" {
  let said = match elsewhere_said() {
    Object(m) => {
      let o = m.copy()
      o["time"] = @sffixture.ago("3 分钟前", "2026-11-11 21:04")
      Json::object(o)
    }
    j => j
  }
  let t = elsewhere_chat(said)
  t.run_for(@ui.move_most_ms)
  guard t.find("3 分钟前") is Some((x, y)) else { fail("no time: \{Repr(t.words().map(fn(w) { w.0 }))}") }
  assert_true(t.find("2026-11-11 21:04") is None, msg="\{x}")
  t.tap_text("3 分钟前")
  t.run_for(@ui.move_most_ms)
  guard t.find("2026-11-11 21:04") is Some((_, ay)) else { fail("not when: \{Repr(t.words().map(fn(w) { w.0 }))}") }
  assert_true((ay - y).abs() < 4.0, msg="\{Repr((y, ay))}")
  t.tap_text("2026-11-11 21:04")
  t.run_for(@ui.move_most_ms)
  guard t.find("3 分钟前") is Some((_, by)) else { fail("not how long ago: \{Repr(t.words().map(fn(w) { w.0 }))}") }
  assert_true((by - y).abs() < 4.0, msg="\{Repr((y, by))}")
}
