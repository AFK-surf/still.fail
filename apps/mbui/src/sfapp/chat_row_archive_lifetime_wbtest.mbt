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
  let tree = @ui.view_tree().unwrap()
  let held = t.drawn_words_found()
  let rows = tree.rows_alive()
  let mut swiped : @view.NodeId? = None
  for i, (_, _, _, words, _) in held {
    if words.contains(title) {
      let mut at = i
      while at >= 0 {
        let (node, parent, _, _, _) = held[at]
        if rows.contains(node.id) {
          swiped = Some(node.id)
          break
        }
        at = parent
      }
    }
  }
  let swiped = match swiped {
    Some(id) => id
    None => fail("the title belongs to a list row")
  }
  t.drag(340.0, y, 120.0, y)
  assert_eq(named(calls, "chat.archive").length(), 0, msg="the row is still moving away")
  t.wheel(150.0, 422.0, 7000.0)
  if every_frame {
    t.run_for(@ui.move_most_ms)
  } else {
    t.advance(@ui.move_most_ms)
    t.frame()
  }
  assert_false(tree.rows_alive().contains(swiped), msg="the swiped row was released")
  named(calls, "chat.archive").length()
}

///|
test "a swipe archives the chat even when its row is recycled before the motion ends" {
  assert_eq(archive_scrolled_away(true), 1, msg="continuous display frames")
  assert_eq(archive_scrolled_away(false), 1, msg="only the end frame")
}

///|
test "a rejected archive can be retried after its row has been recycled" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="long", w=390.0, h=844.0, platform=2, wrap=fn(base) {
    { ..base, call: fn(name, params, done) {
      if name != "chat.archive" { (base.call)(name, params, done) }
    } }
  })
  t.check_looks(false)
  list_down(t, 5)
  let title = "把旧的截图都换成新的"
  let (_, y) = t.find(title).unwrap()
  let tree = @ui.view_tree().unwrap()
  let (first, last) = tree.list_rows().unwrap()
  let mut row_index = -1
  for i in first..=last {
    match tree.list_row(i) {
      Some((_, top, _, height)) if y >= top && y < top + height => { row_index = i; break }
      _ => ()
    }
  }
  assert_true(row_index >= 0, msg="the chat is a visible list row")
  t.drag(340.0, y, 120.0, y)
  t.wheel(150.0, 422.0, 7000.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 1)
  (named(calls, "chat.archive")[0].done)(Err({ "message": "试一次没有成功" }))
  t.scroll_to(if row_index > 1 { row_index - 1 } else { 0 })
  t.frame()
  t.run_for(@ui.move_most_ms)
  let (_, again_y) = match t.locate("=" + title) {
    [at, ..] => at
    _ => fail("the rejected chat is back in its list")
  }
  t.drag(340.0, again_y, 120.0, again_y)
  t.run_for(@ui.move_most_ms)
  let asked = named(calls, "chat.archive").length()
  assert_eq(asked, 2, msg="the same chat can be archived again: row at \{again_y}, asked \{asked}")
}
