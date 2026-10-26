// What changes a chat's list's height plays one at a time (turns.mbt, ListTurns.kt): each from where the one before
// was declared to end, the list at rest.

///|
test "turns: a row comes in at once when none plays; a change asked after it waits its 320 ms, then holds the next" {
  reset()
  let tu = turns_of("test")
  let phase = Ref::new(0)
  let t = @ui.Tester::new(
    fn(c) {
      tu.step(c, -1.0)
      match phase.val {
        0 => {
          ignore(tu.in_turn(c, "k", true, close_turn_ms))
          tu.admit(c, "a", row_turn_ms)
          phase.val = 1
        }
        1 => {
          // (asked after the row: its turn after the row's)
          ignore(tu.in_turn(c, "k", false, close_turn_ms))
          tu.admit(c, "b", row_turn_ms)
          phase.val = 2
        }
        _ => ignore(tu.in_turn(c, "k", false, close_turn_ms))
      }
      c.box(fn() {  }) |> ignore
    },
    w=100.0,
    h=100.0,
    platform=2,
  )
  t.draw()
  t.draw()
  let a_at = tu.started_at("a")
  assert_true(a_at >= 0.0)
  assert_false(tu.waiting.contains("a"))
  // the change and the next row wait for the row's turn
  assert_eq(tu.shown.get("k"), Some(true))
  assert_true(tu.waiting.contains("b"))
  // (each turn holds the next two frames past its motion: turn_calm_ms)
  t.run_for(row_turn_ms + turn_calm_ms)
  assert_eq(tu.shown.get("k"), Some(false))
  assert_eq(tu.started_at("k"), a_at + row_turn_ms + turn_calm_ms)
  assert_true(tu.waiting.contains("b"))
  // the close holds the next row for its 520 ms
  t.run_for(close_turn_ms + turn_calm_ms)
  assert_false(tu.waiting.contains("b"))
  assert_true((tu.started_at("b") - (a_at + row_turn_ms + close_turn_ms + 2.0 * turn_calm_ms)).abs() < 0.001)
  t.assert_idle()
}

///|
test "turns: the next waits for the list at rest (its glide's declared end), not only the turn before" {
  reset()
  let tu = turns_of("test")
  let rest = Ref::new(-1.0)
  let phase = Ref::new(0)
  let t = @ui.Tester::new(
    fn(c) {
      tu.step(c, rest.val)
      if phase.val == 0 {
        tu.admit(c, "a", row_turn_ms)
        tu.admit(c, "b", row_turn_ms)
        phase.val = 1
      }
      c.box(fn() {  }) |> ignore
    },
    w=100.0,
    h=100.0,
    platform=2,
  )
  t.draw()
  t.draw()
  let a_at = tu.started_at("a")
  // the list glides after what came till a while past it
  rest.val = a_at + row_turn_ms + test_glide_ms
  t.run_for(row_turn_ms)
  assert_true(tu.waiting.contains("b"))
  t.run_for(test_glide_ms)
  assert_false(tu.waiting.contains("b"))
  assert_eq(tu.started_at("b"), a_at + row_turn_ms + test_glide_ms)
}

///|
test "a decision answered here: your answer flies from the option to its place, the options none pressed meanwhile, closing once it has landed" {
  // (the fixture's own core: it answers the card, and posts the answer as yours)
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  open_fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.nav_push_ms)
  t.move(195.0, 400.0)
  for _ in 0..<6 {
    if t.find("把首页和聊天页的截图都更新") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  // (the option's detail, under its label)
  let (_, dy) = t.find("把首页和聊天页的截图都更新").unwrap()
  t.tap_text("把首页和聊天页的截图都更新")
  t.draw()
  t.draw()
  t.draw()
  let tu = turns_of("ws1/st1\u{1}s-c1")
  // your answer is in the list at once, its words flying there from the option picked, as words sent from the
  // composer fly; the options still there meanwhile
  let f = match send_flight.val {
    Some(f) => f
    None => fail("the answer flies")
  }
  assert_true(f.from_card && f.placed)
  assert_true(f.from_y < dy && f.from_y > dy - 40.0, msg="from the option: \{f.from_y} over \{dy}")
  let lands = f.way.ends()
  t.run_for(lands - t.time())
  t.draw()
  assert_true(send_flight.val is None)
  assert_eq(tu.shown.get("ask/ts8"), Some(true))
  // then they close, in the turn after its landing
  let at = tu.start_of("ask/ts8")
  assert_true(at >= lands && at < @double.infinity)
  t.run_for(at - t.time())
  assert_eq(tu.shown.get("ask/ts8"), Some(false))
  t.run_for(under_rest() - t.time())
  assert_true(t.find("你 选择了「一起换」") is Some(_))
  assert_true(t.find("把首页和聊天页的截图都更新") is None)
}

///|
/// How long the test's list says it glides after what came (its declared rest, Turns::step's `list_rest`).
let test_glide_ms : Double = 500.0

///|
test "turns: words sent wait for nothing (a row before them, a list never at rest); what is asked after them waits for their landing" {
  reset()
  let tu = turns_of("test")
  let phase = Ref::new(0)
  let t = @ui.Tester::new(
    fn(c) {
      // (an answer streaming in: the list never at rest)
      tu.step(c, @double.infinity)
      match phase.val {
        0 => {
          tu.admit(c, "a", row_turn_ms)
          tu.send(c, flight_wait_ms + flight_ms)
          tu.admit(c, "b", row_turn_ms)
          phase.val = 1
        }
        _ => ()
      }
      c.box(fn() {  }) |> ignore
    },
    w=100.0,
    h=100.0,
    platform=2,
  )
  t.draw()
  t.draw()
  // (sending holds nothing of what was sent: no turn of its own)
  assert_true(tu.asks.iter().all(fn(a) { a.what != Send }))
  // the row asked after them waits for their landing, said as they land
  assert_true(tu.waiting.contains("b"))
  let landed = t.time()
  tu.over(t.ctx(), Send, landed)
  assert_eq(tu.sent_until, landed + turn_calm_ms)
}
