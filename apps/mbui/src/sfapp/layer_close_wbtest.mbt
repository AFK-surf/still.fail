// A layer presented over the frame (sf's presenters: a menu, a question) closed at its cause's moment: back, Escape, a
// press outside it, whatever frames come; what it lets go of as it closes unsaid told once.

///|
/// 大屏, chat A then B opened, a menu shown from the sidebar (its `gone` counted), frames drawn: then `how` (0 back, 1
/// Escape, 2 a press outside it), no frame after: whether a presenter is open then; after frames, whether one is, how
/// many times the menu's `gone` was told then and after frames, the chat on top.
fn closed_by(how : Int) -> (Bool, Int, Bool, Int, String) {
  let (t, _, _) = wide_backs(true)
  open_chat(chat_b)
  t.run_for(@ui.move_most_ms)
  let gone = Ref(0)
  @sf.menu([Some(@sf.menu_item_of("一项", fn() {  }))], from=@sf.at_point(600.0, 300.0), gone=fn() {
    gone.val += 1
  })
  t.run_for(@ui.move_most_ms)
  guard @sf.presenting() else { return (false, -1, false, -1, "no menu") }
  let at = t.time()
  match how {
    0 => t.back_raw(2, 0.0, at)
    1 => t.key_told(@ui.key_escape, 0, at)
    _ => {
      t.touch_raw(0, 1, 40.0, 780.0, at)
      t.touch_raw(2, 1, 40.0, 780.0, at)
    }
  }
  let at_once = (@sf.presenting(), gone.val)
  t.run_for(@ui.move_most_ms)
  (at_once.0, at_once.1, @sf.presenting(), gone.val, top_session())
}

///|
test "大屏: a menu presented, back with no frame after: closed at once, its gone told once, the chat kept" {
  assert_eq(closed_by(0), (false, 1, false, 1, "s-c2"))
}

///|
test "大屏: a menu presented, Escape with no frame after: closed at once, its gone told once, the chat kept" {
  assert_eq(closed_by(1), (false, 1, false, 1, "s-c2"))
}

///|
test "大屏: a menu presented, a press outside it with no frame after: closed at once, its gone told once" {
  let got = closed_by(2)
  assert_eq((got.0, got.1, got.2, got.3), (false, 1, false, 1))
}

///|
test "大屏: a menu, a question presented over it: Escape with no frame after closes the question alone, the menu still open; again, the menu" {
  let (t, _, _) = wide_backs(true)
  let gone = Ref(0)
  @sf.menu([Some(@sf.menu_item_of("一项", fn() {  }))], from=@sf.at_point(600.0, 300.0), gone=fn() { gone.val += 1 })
  t.run_for(@ui.move_most_ms)
  @sf.confirm("删除", "删除这个对话？", "删除", fn() {  })
  t.run_for(@ui.move_most_ms)
  let at = t.time()
  t.key_told(@ui.key_escape, 0, at)
  let first = (@sf.presenting(), gone.val)
  t.key_told(@ui.key_escape, 0, at)
  assert_eq((first, @sf.presenting(), gone.val), ((true, 0), false, 1))
}

///|
test "大屏: a menu closed by Escape with no frame after, then a press where its item was: nothing chosen" {
  let (t, _, _) = wide_backs(true)
  let chosen = Ref(0)
  @sf.menu([Some(@sf.menu_item_of("一项", fn() { chosen.val += 1 }))], from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  let (x, y, w, h) = t.rect_of("一项").unwrap()
  let at = t.time()
  t.key_told(@ui.key_escape, 0, at)
  t.touch_raw(0, 1, x + w / 2.0, y + h / 2.0, at)
  t.touch_raw(2, 1, x + w / 2.0, y + h / 2.0, at)
  t.run_for(@ui.move_most_ms)
  assert_eq((@sf.presenting(), chosen.val), (false, 0))
}

///|
test "大屏: a menu, the system's back gesture begun and called off, no frame between: still open" {
  let (t, _, _) = wide_backs(true)
  @sf.menu([Some(@sf.menu_item_of("一项", fn() {  }))], from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  let at = t.time()
  t.back_raw(0, 0.0, at)
  t.back_raw(1, 60.0, at)
  t.back_raw(3, 60.0, at)
  assert_true(@sf.presenting())
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
}
