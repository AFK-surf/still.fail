// Entering and leaving a chat runs every effect it sets off one at a time (mbui's signals: a flush never runs inside
// another). 2026-11-05: the window's tree's watches each nested a flush in the one under way, as deep as the effects a
// page's change went on to; on the Wasm builds the GL thread ran out of stack as a chat was entered or left.

///|
test "leaving a long chat on a phone runs its effects one inside another at most twice" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-long", w=390.0, h=844.0, platform=2)
  t.set_frame_period(1000.0 / 120.0)
  t.run_for(@ui.move_most_ms)
  @signals.effect_nesting_most() |> ignore
  t.back_told(t.time())
  t.run_as_host(@ui.move_most_ms)
  assert_true(@signals.effect_nesting_most() <= 2)
}

///|
test "entering a chat from the list on a phone runs its effects one inside another at most twice" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="long", w=390.0, h=844.0, platform=2)
  t.set_frame_period(1000.0 / 120.0)
  t.run_for(@ui.move_most_ms)
  @signals.effect_nesting_most() |> ignore
  match t.find("整理发布清单") {
    Some((x, y)) => {
      t.touch_at(0, x, y, t.time())
      t.touch_at(2, x, y, t.time())
    }
    None => abort("no chat in the list")
  }
  t.run_as_host(@ui.move_most_ms)
  let entering = @signals.effect_nesting_most()
  t.back_told(t.time())
  t.run_as_host(@ui.move_most_ms)
  let leaving = @signals.effect_nesting_most()
  assert_eq((entering <= 2, leaving <= 2), (true, true), msg="entering \{entering}, leaving \{leaving}")
}
