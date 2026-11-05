// The message's menu key has the same quiet and active ink as the old view's icon button.

///|
// The comparison's wheel, pause before the pointer sweep, and option press from the recorded sequence.
let more_ink_wheel_pause_ms = 400.0

///|
let more_ink_probe_pause_ms = 1500.0

///|
let more_ink_press_ms = 80.0

///|
fn more_ink_grid(t : @ui.Tester) -> Unit {
  let mut y = 24.0
  while y < 800.0 {
    let mut x = 24.0
    while x < 1280.0 {
      t.probe_at(x, y) |> ignore
      x += 48.0
    }
    y += 48.0
  }
  t.move(1330.0, 850.0)
}

///|
fn more_ink_card_y(t : @ui.Tester) -> Double? {
  for (words, _, y, _, h, a) in t.words() {
    if a > 0.5 && words.contains("等 林 决定") && y + h > 0.0 && y < 800.0 { return Some(y) }
  }
  None
}

///|
fn more_ink_find_card(t : @ui.Tester) -> Unit raise {
  let mut k = 0
  let banded = fn() { more_ink_card_y(t).map_or(false, fn(y) { y > 160.0 && y < 560.0 }) }
  while k < 30 && !banded() {
    let below = more_ink_card_y(t).map_or(false, fn(y) { y >= 560.0 })
    t.wheel(793.6, 400.0, if below { 100.0 } else { -150.0 })
    t.run_for(more_ink_wheel_pause_ms)
    k += 1
  }
  assert_true(banded(), msg="the decision card reached the comparison band")
}

///|
test "after choosing a card option the message menu icon keeps its quiet ink" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", w=1280.0, h=800.0, platform=0)
  t.export_frames()
  t.set_frame_period(1000.0 / 60.0)
  t.run_for(@ui.move_most_ms * 2.0)
  more_ink_grid(t)
  more_ink_find_card(t)
  t.run_for(more_ink_probe_pause_ms)
  more_ink_grid(t)
  let choices = t.semantics().filter(fn(n) {
    !n.hidden && "\{n.role}" == "Button" && (n.label == "一起换" || n.label.has_prefix("一起换 "))
  })
  assert_eq(choices.length(), 1, msg="the actual option, not the message containing its words")
  let (x, y, w, h) = choices[0].rect
  println("MOREINK option=\{choices[0].label} rect=\{choices[0].rect}")
  t.touch_at(0, x + w / 2.0, y + h / 2.0, t.time())
  t.run_for(more_ink_press_ms)
  t.touch_at(2, x + w / 2.0, y + h / 2.0, t.time())
  t.run_for(@ui.move_most_ms * 3.0)
  assert_eq(named(calls, "decision.answer").length(), 1, msg="the option was answered")
  let dots = t.frame_export().filter(fn(s) {
    s.has_prefix("shape 1149.5 326 ") || s.has_prefix("shape 1154 326 ") || s.has_prefix("shape 1158.5 326 ")
  })
  println("MOREINK dots=\{dots}")
  assert_eq(dots.length(), 3, msg="the message menu's three dots are drawn")
  assert_true(dots.iter().all(fn(s) { s.contains("#535559") }), msg="the quiet ink is the old view's: \{dots}")
}
