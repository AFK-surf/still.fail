// A chat swiped off its row by a finger, past the row's width (the finger already took it all the way off): archived
// as it is let go, its toast with 撤销 there its whole time from then (toast_action_ms), as when the row still slides
// the rest of the way off.

///|
test "a chat's row swiped all the way off by a finger: archived as it is let go, its toast there its whole time" {
  let calls : Array[Made] = []
  let (w, h) = (1280.0, 800.0)
  let t = wide_tester(calls, mode="long", w~, h~, platform=2)
  t.run_for(@ui.move_most_ms * 2.0)
  // (from near the row's right end to past its left: further than the row is wide)
  t.drag(255.0, h * 0.45, 30.0, h * 0.45, steps=16)
  let let_go = t.time()
  t.run_for(@ui.move_most_ms)
  assert_true(app.toast.get().words.contains("已归档"), msg="no toast: \{app.toast.get().words}")
  t.run_for(let_go + @sf.toast_action_ms - 400.0 - t.time())
  assert_true(app.toast.get().words.contains("已归档"), msg="gone before its time, at \{t.time() - let_go} ms")
  assert_true(t.words().iter().any(fn(wd) { wd.0.contains("已归档") }), msg="not drawn at \{t.time() - let_go} ms")
}
