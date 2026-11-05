// The card over an agent's name casts its shadow outside its box, as a small panel does.

///|
test "an agent's hover card casts its shadow outside the card" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.find("Claude").unwrap()
  t.move(x, y)
  t.frame()
  t.run_for(@sfpages.hover_open_ms * 2.0)
  t.frame()
  // A small panel casts a rounded 16-point shadow, 12 points below its box. Its draw clip must leave it visible
  // at least 8 points beyond each edge, not cut it square to the island's layout box.
  let shadows = t.drawn_cut().filter(fn(d) { d.0 == 2 && d.1 > 300.0 && d.3 >= 200.0 && d.3 <= 420.0 && d.4 < 200.0 })
  assert_false(shadows.is_empty(), msg="the agent's card has a shadow")
  let s = shadows[0]
  let round = t.drawn_shadows().filter(fn(d) { d.0 == s.1 && d.1 == s.2 && d.2 == s.3 && d.3 == s.4 })
  assert_true(!round.is_empty() && round[0].4 > 0.0 && round[0].5 >= 16.0, msg="the card casts a rounded shadow: \{round}")
  let (left, top, right, bottom) = s.5
  assert_true(left <= s.1 - 8.0 && top <= s.2 - 12.0 - 8.0 && right >= s.1 + s.3 + 8.0 && bottom >= s.2 - 12.0 + s.4 + 8.0,
    msg="the card's shadow is visible 8 points past every edge: \{s}")
}
