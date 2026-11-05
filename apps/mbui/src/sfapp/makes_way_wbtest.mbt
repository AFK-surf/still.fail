// What makes way in a chat's list (an agent's line, what was sent not in the chat yet) moves where it shows only for a
// row that came in over it, that cause (sfpages chat_list makes_way, row_keys's came): not for the page before coming
// in above, not for words sent flying in, not for a message out of its own avatar. Followed at its end, what is at the
// end stays where it shows and the rows over the one that came go up for it (row_keys's over), never down and back.

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
test "followed at its end, a message said over the agent's line: the line stays where it shows, nothing goes down and back" {
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
  // someone says something: it comes in over the line
  let words = "我也看看这个"
  said_by_ana(170, words)
  let mut n = 0
  while t.drawn_of(words) is None && n < 120 {
    t.frame()
    n += 1
  }
  guard t.drawn_of(words) is Some(_) else { fail("「\{words}」 never came in") }
  // every frame from then on: the line where it showed
  let end = t.time() + 800.0
  while t.time() < end {
    let (_, y) = t.drawn_of(working).unwrap()
    assert_true((y - y0).abs() < 1.0, msg="at \{t.time()} the line at \{y}, from \{y0}")
    t.frame()
  }
  guard t.drawn_of(words) is Some((_, wy)) else { fail("「\{words}」 gone") }
  assert_true(wy < y0, msg="the message at \{wy}, the line at \{y0}")
}
