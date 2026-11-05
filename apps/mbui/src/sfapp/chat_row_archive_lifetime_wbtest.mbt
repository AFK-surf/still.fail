///|
/// Swipe a chat to archive it and immediately scroll its row out of the window. The same events are followed either
/// by the display's frames or by one frame at the end of the motion.
fn archive_scrolled_away(every_frame : Bool) -> Int raise {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="long", w=390.0, h=844.0, platform=2)
  t.check_looks(false)
  list_down(t, 5)
  t.draw()
  let title = "把旧的截图都换成新的"
  let (_, y) = match t.find(title) {
    Some(at) => at
    None => fail("the chat to swipe is in the window")
  }
  t.drag(340.0, y, 120.0, y)
  assert_eq(named(calls, "chat.archive").length(), 0, msg="the row is still moving away")
  let tree = @ui.view_tree().unwrap()
  let was = tree.rows_alive()
  t.wheel(150.0, 422.0, 7000.0)
  if every_frame {
    t.run_for(1200.0)
  } else {
    t.advance(1200.0)
    t.frame()
  }
  let now = tree.rows_alive()
  assert_true(was.iter().any(fn(id) { !now.contains(id) }), msg="the list released rows")
  assert_true(t.find(title) is None, msg="the swiped row left the window")
  named(calls, "chat.archive").length()
}

///|
test "a swipe archives the chat even when its row is recycled before the motion ends" {
  assert_eq(archive_scrolled_away(true), 1, msg="continuous display frames")
  assert_eq(archive_scrolled_away(false), 1, msg="only the end frame")
}
