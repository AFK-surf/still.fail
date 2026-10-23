// An agent's line coming in, each turn of its agent's (Chat.kt Activity): its room opens as it grows from its avatar
// and fades in, carrying what is above it up, its second turn as its first. Its key is its agent's, the same each
// turn: gone from the chat, it is new to the list again.

///|
/// Words just sent in the fixture's chat (`words`), delivered: its agent at work, its line asked to come in. Where the
/// words are drawn (y) as its room starts opening (its turn's declared start), halfway (half its 220 ms) and at its end.
fn activity_opening(t : @ui.Tester, words : String) -> (Double, Double, Double) raise {
  t.run_for(fix_deliver_ms)
  let at = turns_of("ws1/st1\u{1}s-c1").start_of("act:s-c1")
  assert_true(at >= t.time() && at < @double.infinity, msg="\{at} \{t.time()}")
  t.run_for(at - t.time())
  let (_, from) = t.drawn_of(words).unwrap()
  t.run_for(working_turn_ms / 2.0)
  let (_, mid) = t.drawn_of(words).unwrap()
  t.run_for(working_turn_ms / 2.0)
  let (_, end) = t.drawn_of(words).unwrap()
  (from, mid, end)
}

///|
test "an agent's line comes in each turn as in its first: its room opening, carrying what is above it up" {
  let t = linger_core()
  let (from1, mid1, end1) = activity_opening(t, "看一下列表")
  assert_true(mid1 < from1 - 1.0 && mid1 > end1 + 1.0, msg="\{from1} \{mid1} \{end1}")
  // its answer out of its avatar, its turn over, its line stayed its moment and gone
  t.run_for(fix_answer_ms + fix_turn_end_ms + emit_all_ms() + linger_ms)
  assert_true(t.find(tr("android-chat.chat.working")) is None)
  // words sent again: its agent at work again, its line coming in as it did the first time
  t.tap_text("发消息")
  t.type_text("再看一下")
  tap_send(t)
  let (from2, mid2, end2) = activity_opening(t, "再看一下")
  assert_true((from2 - from1).abs() < 0.5, msg="\{from2} \{from1}")
  assert_true((mid2 - mid1).abs() < 0.5, msg="\{mid2} \{mid1}")
  assert_true((end2 - end1).abs() < 0.5, msg="\{end2} \{end1}")
}
