// The room an agent's line leaves at the chat's end (chat.mbt floor_of, Chat.kt floor): the list never gets shorter
// under the reader, so nothing over the line drops as it goes; what comes in next takes the room back.

///|
fn floor_now() -> Double {
  match readings.get("ws1/st1\u{1}s-c1") {
    Some(rd) => rd.floor
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
test "an agent's line gone from the chat's end leaves its room: what is over it stays where it is" {
  let t = linger_core()
  // its answer out of its avatar, its turn over: its line stays its moment from there
  t.run_for(fix_deliver_ms + fix_answer_ms + fix_turn_end_ms + emit_all_ms())
  assert_true(t.find(tr("android-chat.chat.working")) is Some(_))
  assert_true(t.at_end())
  let ys = answer_ys(t, linger_ms + 100.0)
  // gone, its room kept under the answer
  assert_true(t.find(tr("android-chat.chat.working")) is None)
  assert_true(floor_now() > 0.0, msg="\{floor_now()}")
  assert_true(ys.length() > 0)
  for y in ys {
    assert_true((y - ys[0]).abs() < 0.5, msg="\{ys}")
  }
  t.assert_idle()
}

///|
test "what is sent after an agent's line went takes its room back" {
  // (the list then as it would have been without it: activity_again_wbtest, its line's second turn where its first was)
  let t = linger_core()
  t.run_for(fix_deliver_ms + fix_answer_ms + fix_turn_end_ms + emit_all_ms() + linger_ms + 100.0)
  assert_true(floor_now() > 0.0)
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  // its row in the list (the core's at once: this fixture's outbox), as tall as the room or taller
  t.run_for(flight_ms)
  assert_eq(floor_now(), 0.0)
  assert_true(t.at_end())
}
