// An agent's activity staying a moment once its turn is over (chat.mbt chat_tick, Chat.kt lingering): on the time that
// goes by, whatever page shows; while its messages still come out of its avatar it stays, its moment from the last.

///|
/// The fixture's chat open, on the frames' clock; words sent (its agent then at work, answering, its turn ending).
fn linger_core() -> @ui.Tester {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("看一下列表")
  tap_send(t)
  t
}

///|
fn lingering() -> Int {
  match readings.get("ws1/st1\u{1}s-c1") {
    Some(rd) => rd.linger.length()
    None => -1
  }
}

///|
test "its turn over while another page covers its chat: its moment goes by meanwhile, gone as the chat shows again" {
  let t = linger_core()
  // scrolled up: its answer just appears (nothing comes out of an avatar)
  t.run_for(fix_deliver_ms)
  t.wheel(195.0, 400.0, -600.0)
  t.run_for(fix_answer_ms)
  assert_eq(lingering(), 0)
  // another page over the chat; its agent's turn over under it, a second gone by
  app.nav.push(Settings)
  t.run_for(@ui.move_most_ms)
  t.run_for(fix_turn_end_ms + 1000.0)
  t.back()
  t.draw()
  // the chat shown again: its activity's moment went by under the page (Chat.kt: on the time that goes by)
  assert_eq(lingering(), 0)
  t.run_for(@ui.move_most_ms)
  assert_eq(lingering(), 0)
  t.assert_idle()
}

///|
test "its answer out of its avatar past its activity's whole stay: it stays its moment from when the last is out" {
  let t = linger_core()
  let em = emits_of("ws1/st1\u{1}s-c1")
  let mut turn_over_at = -1.0
  let mut last_keep_at = -1.0
  let mut gone_at = -1.0
  let end = t.time() + fix_deliver_ms + fix_answer_ms + fix_turn_end_ms + 4000.0
  while t.time() < end {
    t.frame()
    let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
    if rd.linger.length() > 0 && turn_over_at < 0.0 {
      turn_over_at = t.time()
    }
    if turn_over_at >= 0.0 && !emit_keeps(em).is_empty() {
      last_keep_at = t.time()
    }
    if turn_over_at >= 0.0 && rd.linger.length() == 0 && gone_at < 0.0 {
      gone_at = t.time()
    }
  }
  // its turn over while its answer was still coming out of its avatar, the way out longer than the whole stay
  assert_true(turn_over_at >= 0.0 && last_keep_at > turn_over_at)
  assert_true(emit_all_ms() > linger_ms)
  // its moment from the last frame its answer was still coming: gone 600 ms on (the frame that reaches it)
  let frame = 16.0
  assert_true(gone_at >= last_keep_at + linger_ms && gone_at < last_keep_at + linger_ms + frame)
  t.assert_idle()
}
