// The settings' sidebar made once (sfdesk's settings_side_node) beside the settings' pages on a large screen: where it
// is scrolled to kept as it is left and come back to and as the sidebar folds and opens again; a mouse's drag of its
// list's thumb under the sidebar's edge scrolls the list, the edge left as it is; the edge dragged beside it, the
// sidebar wider.

///|
/// The settings opened on a large screen, the window 430 tall (its list taller than its room), with keyboard and mouse
/// (its buttons in the app's top row: `window_inset`).
fn settings_side_tester(window_inset? : Bool = false) -> @ui.Tester {
  let t = wide_tester([], mode="settings", h=430.0, platform=0, window_inset~)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "the settings' sidebar made once: where it is scrolled to kept as it is left for the chats and come back to, and as it folds and opens" {
  let t = settings_side_tester()
  let (x, top, _, _) = t.rect_of("返回会话").unwrap()
  let (_, before, _, _) = t.rect_of("本机缓存").unwrap()
  t.wheel(x, top + 200.0, 3000.0)
  t.run_for(@ui.move_most_ms)
  let (_, scrolled, _, _) = t.rect_of("本机缓存").unwrap()
  assert_true(scrolled < before, msg="scrolled: \{before} to \{scrolled}")
  // (back to the chats, the settings again)
  t.tap_text("返回会话")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("新建对话") is Some(_))
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.rect_of("本机缓存").map(fn(r) { r.1 }), Some(scrolled), msg="come back to")
  // (folded and opened again: its top row and where it is scrolled to as they were)
  let back = t.rect_of("返回会话")
  @sfdesk.wide.folded.set(true)
  t.run_for(@ui.move_most_ms)
  @sfdesk.wide.folded.set(false)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.rect_of("返回会话"), back, msg="its top row")
  assert_eq(t.rect_of("本机缓存").map(fn(r) { r.1 }), Some(scrolled), msg="folded and opened")
}

///|
test "the settings' sidebar made once: its list's thumb under the sidebar's edge dragged by a mouse scrolls the list, the sidebar as wide; the edge dragged beside it, wider" {
  let t = settings_side_tester()
  let tree = @ui.view_tree().unwrap()
  let w0 = @sfdesk.wide.side_w.get()
  // (the thumb shown: the list scrolled a little)
  let (x, top, _, _) = t.rect_of("返回会话").unwrap()
  t.wheel(x, top + 200.0, 40.0)
  t.run_for(@ui.move_most_ms / 4.0)
  // (its list's thumb: where it is placed in the window, cut to what bounds its input; the sidebar's, left of the
  // page)
  let thumbs = tree
    .thumbs_now()
    .filter_map(fn(id) {
      guard tree.view_of(id) is Some(v) else { return None }
      let (x, y, w, h) = v.placed_window_now()
      let (x0, y0, x1, y1) = tree.input_bounds(id)
      let (a, b, c, d) = (dmax(x, x0), dmax(y, y0), dmin(x + w, x1), dmin(y + h, y1))
      if c > a && d > b && a < w0 + 100.0 {
        Some((id, (a, b, c, d)))
      } else {
        None
      }
    })
  assert_true(thumbs.length() == 1, msg="its list's thumb: \{thumbs.map(fn(t) { t.1 })}")
  let (thumb, (bx0, by0, bx1, by1)) = thumbs[0]
  let (px, py) = (bx1 - 1.0, (by0 + by1) / 2.0)
  // (what the tree finds there: the thumb itself)
  assert_eq(tree.target_at(px, py), @view.Target::Dragged(thumb), msg="the thumb taken there")
  let (_, before, _, _) = t.rect_of("本机缓存").unwrap()
  // (at the thumb's right end, under the edge's strip)
  t.drag(px, py, px, py + 60.0)
  t.run_for(@ui.move_most_ms)
  let (_, after, _, _) = t.rect_of("本机缓存").unwrap()
  assert_true(after < before, msg="the list scrolled: \{before} to \{after}")
  assert_eq(@sfdesk.wide.side_w.get(), w0, msg="the sidebar as wide")
  // (the edge dragged where no thumb is: low in the window, the thumb up the list)
  let edge_x = bx1 + 2.0
  ignore(bx0)
  t.drag(edge_x, 420.0, edge_x + 40.0, 420.0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.side_w.get() > w0, msg="the edge dragged: \{w0} to \{@sfdesk.wide.side_w.get()}")
}

///|
test "the settings' sidebar made once: its top row drags the window while the window's buttons are in it and the sidebar is open, as that changes" {
  let t = settings_side_tester(window_inset=true)
  // (over 返回会话, in the top row)
  let (x, top, _, _) = t.rect_of("返回会话").unwrap()
  let y = top / 2.0
  assert_true(t.drags_window_at(x, y), msg="its buttons in the top row")
  // (full screen: the system's, nothing of the app's drags it)
  t.set_window_inset(false)
  t.run_for(@ui.move_most_ms)
  assert_true(!t.drags_window_at(x, y), msg="full screen")
  t.set_window_inset(true)
  t.run_for(@ui.move_most_ms)
  assert_true(t.drags_window_at(x, y), msg="out of full screen")
  // (folded and opened again)
  @sfdesk.wide.folded.set(true)
  t.run_for(@ui.move_most_ms)
  @sfdesk.wide.folded.set(false)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.rect_of("返回会话").map(fn(r) { r.1 }), Some(top), msg="opened again")
  assert_true(t.drags_window_at(x, y), msg="opened again: its top row drags it")
}
