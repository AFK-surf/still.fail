// 小屏: a person's act pressed on a node of the window's tree is an entry of the history once its change is told whole
// (sfbase's history_push), not once an old view is built after it: Home's settings pressed, then back and forward with
// no frame between, the settings on top again, as with frames.

///|
test "小屏: Home's settings pressed, back, forward, no frame between: the settings on top again, an act done as it is pressed" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let t = wide_tester(calls, mode="long", w=390.0, h=844.0, platform=2, before=fn(s) { made.val = Some(s) })
  t.run_for(@ui.move_most_ms * 2.0)
  let ended = @sfbase.history_acts_ended()
  let settings = t.semantics().iter().find_first(fn(s) { !s.hidden && s.role == Button && s.label == "设置" }).unwrap()
  let (x, y, w, h) = settings.rect
  // (a finger's tap as the host hands it: down and up at one moment, no frame after)
  t.touch_at(0, x + w / 2.0, y + h / 2.0, t.time())
  t.touch_at(2, x + w / 2.0, y + h / 2.0, t.time())
  assert_true(app.nav.top() is Settings, msg="settings pushed")
  assert_eq(@sfbase.history_acts_ended(), ended + 1, msg="the act said done as its press is")
  @sfbase.go_back() |> ignore
  assert_true(app.nav.top() is Home, msg="back to Home")
  @sfbase.go_forward(made.val.unwrap()) |> ignore
  assert_true(app.nav.top() is Settings, msg="forward to the settings")
}
