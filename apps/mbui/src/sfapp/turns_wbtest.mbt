// What changes a chat's list's height under a post plays one at a time (turns.mbt, ListTurns.kt): each from where the
// one before was declared to end. No row waits for a turn: messages are on screen first.

///|
test "turns: a change comes at once when none plays; one asked after it waits for its declared end, then holds the next" {
  reset()
  let tu = turns_of("test")
  let phase = Ref::new(0)
  let t = @ui.Tester::new(
    fn(c) {
      tu.step(c)
      match phase.val {
        0 => {
          ignore(tu.in_turn(c, "k", true, close_turn_ms))
          ignore(tu.in_turn(c, "j", true, dismiss_turn_ms))
          phase.val = 1
        }
        1 => {
          ignore(tu.in_turn(c, "k", false, close_turn_ms))
          ignore(tu.in_turn(c, "j", false, dismiss_turn_ms))
          phase.val = 2
        }
        _ => {
          ignore(tu.in_turn(c, "k", false, close_turn_ms))
          ignore(tu.in_turn(c, "j", false, dismiss_turn_ms))
        }
      }
      c.box(fn() {  }) |> ignore
    },
    w=100.0,
    h=100.0,
  )
  t.draw()
  t.draw()
  t.draw()
  let k_at = tu.started_at("k")
  assert_true(k_at >= 0.0)
  assert_eq(tu.shown.get("k"), Some(false))
  // the next waits for the first's motion (and two frames past it: turn_calm_ms)
  assert_eq(tu.shown.get("j"), Some(true))
  t.run_for(close_turn_ms + turn_calm_ms)
  assert_eq(tu.shown.get("j"), Some(false))
  assert_true((tu.started_at("j") - (k_at + close_turn_ms + turn_calm_ms)).abs() < 0.001)
  t.assert_idle()
}

///|
test "a decision answered: the answer in the list at once, the options closing in their turn, how it went in their place" {
  // (the fixture's own core: it answers the card, and posts the answer as yours)
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  open_fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.run_for(@ui.nav_push_ms)
  t.move(195.0, 400.0)
  for _ in 0..<6 {
    if t.find("把首页和聊天页的截图都更新") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  t.tap_text("把首页和聊天页的截图都更新")
  t.draw()
  let tu = turns_of("ws1/st1\u{1}s-c1")
  let rd = reading_of("ws1/st1\u{1}s-c1")
  // your answer in the list at once (the reader at the end), rising in; the options closing in their turn
  assert_true(rd.known.contains("m:ts108"))
  assert_true(t.find("你 选择了「一起换」") is Some(_))
  t.draw()
  let at = tu.start_of("ask/ts8")
  assert_true(at < @double.infinity)
  t.run_for(at - t.time())
  assert_eq(tu.shown.get("ask/ts8"), Some(false))
  assert_eq(tu.started_at("ask/ts8"), at)
  t.run_for(under_rest() - t.time())
  assert_true(t.find("你 选择了「一起换」") is Some(_))
  assert_true(t.find("把首页和聊天页的截图都更新") is None)
}
