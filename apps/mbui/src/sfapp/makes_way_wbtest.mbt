// What makes way in a chat's list (an agent's line, what was sent not in the chat yet) glides down when a row comes in
// over it, for that cause (sfpages chat_list makes_way, row_keys's came): not for the page before coming in above, not
// for words sent flying in, not for a message out of its own avatar.

///|
/// Someone says `words` in the fixture's chat a moment from now (said while it shows: new to the list).
fn said_by_ana(seq : Int, words : String) -> Unit {
  fix_later(fix_said_ms, fn() {
    fix_chat("s-c1").sent.push(
      msg(seq, "person", by_person("安娜"), words, "刚刚", { "ts": Json::string("ana\{seq}"), "said": true }),
    )
  })
}

///|
/// How soon after it is asked the test's message is said.
let fix_said_ms : Double = 1.0

///|
test "an agent's line pushed down by a message said over it glides there, drawn from where it was" {
  let t = linger_core()
  let working = tr("android-chat.chat.working")
  // its line in at the chat's end, the list there
  t.run_for(fix_deliver_ms)
  let at = turns_of("ws1/st1\u{1}s-c1").start_of("act:s-c1")
  t.run_for(at - t.time() + working_turn_ms)
  let rest = t.rest_of("a list")
  if rest > t.time() && rest < @double.infinity {
    t.run_for(rest - t.time())
  }
  let (_, y0) = t.drawn_of(working).unwrap()
  // someone says something: it comes in over the line, which is pushed down by it
  let words = "我也看看这个"
  said_by_ana(160, words)
  let mut n = 0
  while t.drawn_of(words) is None && n < 120 {
    t.frame()
    n += 1
  }
  guard t.drawn_of(words) is Some((_, wy)) else { fail("「\{words}」 never came in") }
  let (_, y1) = t.drawn_of(working).unwrap()
  // the frame it comes: the line still drawn where it was (laid out under the message, on its way there), not put
  // there at once
  assert_true((y1 - y0).abs() < 4.0 && y1 < wy + 20.0, msg="the line at \{y1}, from \{y0}; the message at \{wy}")
}
