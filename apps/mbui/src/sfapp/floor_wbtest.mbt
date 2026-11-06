// The room an agent's line leaves at the chat's end (chat.mbt floor_of, Chat.kt floor): the list never gets shorter
// under the reader at once: nothing over the line drops as it goes; the rows over it make way from where they stood (on
// the rows' spring, docs/motion.md kind 3), and what comes in meanwhile takes the room back.

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
test "an agent's line gone from the chat's end: what is over it makes way, nothing dropped at once" {
  let t = linger_core()
  let original_held_at = t.time() + fix_deliver_ms + fix_answer_ms + fix_turn_end_ms + emit_all_ms()
  let original_gone_at = original_held_at + linger_ms + 100.0
  let em = emits_of(emit_chat)
  let rd = reading_of(emit_chat)
  let working = tr("android-chat.chat.working")
  fn state(label : String) {
    let pictures = t.words().filter(fn(w) { w.0.contains(working) })
    let ended = em.ended.get("s-c1")
    let linger = rd.linger.get("s-c1").map(fn(l) { (l.at, dmax(l.at, emit_ended(em, "s-c1")) + linger_ms) })
    println("floor \{label} at \{t.time()}: phase \{em.current.map(fn(p) { (p.pose, p.clock.end()) })}, ended \{ended}, linger \{linger}, node \{t.find(working)}, pictures \{pictures}")
  }
  // its answer out of its avatar, its turn over: its line stays its moment from there
  t.run_for(fix_deliver_ms + fix_answer_ms)
  assert_true(em.current is Some(_), msg="the answer has started its way out")
  let until = t.time() + fix_turn_end_ms + emit_all_ms()
  while em.current is Some(_) && t.time() < until { t.frame() }
  assert_true(em.current is None, msg="the answer finishes before its line's stay is inspected")
  state("reply finished")
  assert_true(t.find(tr("android-chat.chat.working")) is Some(_))
  assert_true(t.at_end())
  let ys = answer_ys(t, linger_ms + 100.0)
  state("linger check")
  // Its logical stay has ended. The departing row can still be drawn while its room closes; keep observing that
  // whole departure below, rather than requiring its picture gone only 100 ms into the row's 300 ms way.
  assert_eq(lingering(), 0)
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
  assert_true(t.find(tr("android-chat.chat.working")) is None)
  state("departure finished")
  assert_eq(floor_now(), 0.0)
  assert_true(t.at_end())
  t.assert_idle()
  // Preserve the former absolute sampling times as well as the cause-relative checks above. They follow the
  // complete departure; no picture is inserted into a reply's handover to make its endpoint available.
  if t.time() <= original_held_at { t.run_for(original_held_at - t.time()); state("original held sample") }
  assert_true(t.time() <= original_gone_at, msg="the complete departure must fit before the original gone sample")
  t.run_for(original_gone_at - t.time())
  state("original gone sample")
  assert_true(t.find(working) is None)
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
