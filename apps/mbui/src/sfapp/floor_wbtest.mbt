// The room an agent's line leaves at the chat's end (chat.mbt floor_of, Chat.kt floor): the list never gets shorter
// under the reader at once: nothing over the line drops as it goes; the rows over it make way from where they stood (on
// the rows' spring, docs/motion.md kind 3), and what comes in meanwhile takes the room back.

///|
fn floor_now() -> Double {
  match readings.get("ws1/st1\u{1}s-c1") {
    Some(rd) => rd.floor.get()
    None => -1.0
  }
}

///|
/// Where the agent's answer to 看一下列表 is drawn (its top), each frame from now to `ms` on, and whether its line was
/// still there at the first of them.
fn answer_ys(t : @ui.Tester, ms : Double) -> Array[Double] {
  let ys = []
  let end = t.time() + ms
  while t.time() < end {
    t.frame()
    match t.drawn_of("收到：「看一下列表」") {
      Some((_, y)) => ys.push(y)
      None => ()
    }
  }
  ys
}

///|
test "an agent's line gone from the chat's end: what is over it makes way, nothing dropped at once" {
  let t = linger_core()
  // its answer out of its avatar, its turn over: its line stays its moment from there
  t.run_for(fix_deliver_ms + fix_answer_ms + fix_turn_end_ms + emit_all_ms())
  assert_true(t.find(tr("android-chat.chat.working")) is Some(_))
  assert_true(t.at_end())
  let ys = answer_ys(t, linger_ms + 100.0)
  // gone, its room kept as it goes, given back as the rows over it make way (the rows' spring, from where they stood)
  assert_true(t.find(tr("android-chat.chat.working")) is None)
  assert_true(ys.length() > 1)
  let rest = t.rest_of("")
  if rest > t.time() && rest < @double.infinity {
    let more = answer_ys(t, rest - t.time())
    for y in more {
      ys.push(y)
    }
  }
  // (each frame a step of the spring's, none the line's whole room at once)
  for i in 1..<ys.length() {
    assert_true((ys[i] - ys[i - 1]).abs() < 20.0, msg="\{ys}")
  }
  assert_eq(floor_now(), 0.0)
  assert_true(t.at_end())
  t.assert_idle()
}

///|
test "what is sent as the rows make way for an agent's line gone: no room left, the list at its end" {
  // (the list then as it would have been without it: activity_again_wbtest, its line's second turn where its first was)
  let t = linger_core()
  t.run_for(fix_deliver_ms + fix_answer_ms + fix_turn_end_ms + emit_all_ms() + linger_ms + 100.0)
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  // its row in the list (the core's at once: this fixture's outbox), as tall as the room or taller
  t.run_for(flight_ms)
  assert_eq(floor_now(), 0.0)
  assert_true(t.at_end())
}
