// Back to a layer of the old frame's (a menu, a question presented over the frame): taken by it once, at back's moment,
// back the next time the one it was over's (the history's, a page's own stack) though the layer closes only as it is
// built next; a gesture called off takes nothing of it.

///|
/// 大屏, A then B opened, a chat's menu shown in the sidebar (frames: drawn and said): then back twice with no frame
/// between; then a frame: whether a menu is shown, the chat on top.
fn menu_back_twice() -> (Bool, String) {
  let (t, t0, _) = wide_backs(true)
  open_chat(chat_b)
  t.run_for(@ui.move_most_ms)
  let (x, y, _, h) = t.rect_of("整理发布清单").unwrap()
  t.right_click(x + 4.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  guard @sf.presenting() else { return (false, "no menu") }
  let at = t.time()
  ignore(t0)
  t.back_raw(2, 0.0, at)
  t.back_raw(2, 0.0, at)
  t.run_for(@ui.move_most_ms)
  (@sf.presenting(), top_session())
}

///|
test "大屏: a chat's menu shown, back twice with no frame between: the menu's, then the history's" {
  assert_eq(menu_back_twice(), (false, "s-c1"))
}

///|
/// 中屏 on the tape, the page in use, a chat opened over it (its own stack), then a question presented over the window
/// (frames: drawn and said): back twice with no frame between; then frames: whether it is presented, how deep the stack
/// is, the panel in use.
fn question_over_stack() -> (Bool, Int, @sfdesk.TapePane) {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  page_over(t, 690.0)
  open_chat(chat_b)
  t.run_for(page_local_ms + @ui.move_most_ms)
  @sf.confirm("删除", "删除这个对话？", "删除", fn() {  })
  t.run_for(@ui.move_most_ms)
  // (where it is as back comes: the chat over the page, the question shown)
  guard app.nav.depth() == 3 && top_session() == "s-c2" && @sf.presenting() else {
    return (false, -app.nav.depth(), @sfdesk.wide.tape_at.get())
  }
  let at = t.time()
  t.back_raw(2, 0.0, at)
  t.back_raw(2, 0.0, at)
  t.run_for(@ui.move_most_ms)
  (@sf.presenting(), app.nav.depth(), @sfdesk.wide.tape_at.get())
}

///|
test "中屏: a question over a chat opened over the page, back twice with no frame between: the question's, then the page's own stack's (the chat over it off), the page still in use" {
  assert_eq(question_over_stack(), (false, 2, @sfdesk.TapePane::Page))
}

///|
test "大屏: a chat's menu shown, the system's back gesture begun and called off, then back: the menu's still, the chat on top kept" {
  let (t, _, _) = wide_backs(true)
  open_chat(chat_b)
  t.run_for(@ui.move_most_ms)
  let (x, y, _, h) = t.rect_of("整理发布清单").unwrap()
  t.right_click(x + 4.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  let at = t.time()
  t.back_raw(0, 0.0, at)
  t.back_raw(1, 60.0, at)
  t.back_raw(3, 60.0, at)
  t.back_raw(2, 0.0, at)
  t.run_for(@ui.move_most_ms)
  assert_eq((@sf.presenting(), top_session()), (false, "s-c2"))
}
