// 大屏 with keyboard and mouse: a chat opened from the chats' list and gone back from, the home's field has the cursor
// again (its 做任何事 under it), as the composer's entry rule gives it as its draft changes (composer.mbt): the chat's
// composer a node of the window's tree now, its draft said there as well.

///|
test "大屏 by mouse: back from a chat opened from the list, the home's field has the cursor" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="long", w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms * 2.0)
  let before = t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none")
  // (a row of the list, a third of the way down its side)
  t.move(150.0, 800.0 * 0.3)
  t.press_at(150.0, 800.0 * 0.3)
  t.release(150.0, 800.0 * 0.3)
  t.run_for(@ui.move_most_ms * 2.0)
  t.back()
  t.run_for(@ui.move_most_ms * 2.0)
  let after = t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none")
  assert_eq(after, before, msg="before it opened: \{before}")
  assert_eq(after, "TextField 做任何事")
}
