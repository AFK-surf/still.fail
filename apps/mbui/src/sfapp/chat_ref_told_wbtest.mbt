// The composer's menu of chats to reference (sfpages' chat_ref.mbt: `@` and words) dismissed by the hand: Escape, a
// press away from the composer, closed for that `@` at that input's moment; the frame after closing nothing more.

///|
/// The desk's composer focused, "看 @首页" typed, its menu of chats shown: the Tester, whether that menu is closed for
/// its `@` (sfbase's refs_at none), and its source.
fn ref_menu_tester(calls? : Array[Made] = []) -> (@ui.Tester, () -> Bool, Source) raise {
  let (t, src) = desk_composer_tester(calls)
  desk_focus(t)
  t.type_text("看 @首页")
  t.frame()
  assert_true(t.find("引用对话") is Some(_), msg=t.words().map(fn(x) { x.0 }).join("|"))
  (t, fn() { @sfbase.refs_at("ws1/st1:s-c1") is None }, src)
}

///|
test "desk composer: its menu of chats dismissed by Escape: closed for that @ as the key is taken; the frame after closes nothing more" {
  let (t, closed, _) = ref_menu_tester()
  let seen = [closed()]
  t.key_told(@ui.key_escape, 0, t.time())
  seen.push(closed())
  t.draw()
  seen.push(closed())
  t.run_for(@kit.pop_out_ms)
  assert_eq(seen, [false, true, true])
  assert_true(t.find("引用对话") is None)
  assert_true(t.ctx().editor_focused(@sfpages.composer_field_key), msg="the field keeps the focus")
}

///|
test "desk composer: its menu of chats dismissed by a press away from the composer: closed for that @ as it goes down; the frame after closes nothing more" {
  let (t, closed, _) = ref_menu_tester()
  // (above the menu, away from the composer: a press in the composer is its own, not the menu's dismissal)
  let (x, y) = (450.0, 20.0)
  let seen = [closed()]
  t.touch_at(0, x, y, t.time())
  seen.push(closed())
  t.touch_at(2, x, y, t.time())
  t.draw()
  seen.push(closed())
  assert_eq(seen, [false, true, true])
}

///|
/// A chat pressed in the menu (as the host hands it on), then Escape at once, a frame between or none: how often it was
/// asked to be referenced, the words once the core has made its mark (the fixture's answering it), how often a message was sent, whether the field
/// keeps the focus.
fn ref_picked_then_escape(frames : Bool) -> (Int, String, Int, Bool) raise {
  let calls : Array[Made] = []
  let (t, _, src) = ref_menu_tester(calls~)
  let (cx, cy, cw, ch) = t.rect_of("首页的列表改成按天分组").unwrap()
  t.touch_at(0, cx + cw / 2.0, cy + ch / 2.0, t.time())
  t.touch_at(2, cx + cw / 2.0, cy + ch / 2.0, t.time())
  if frames {
    t.frame()
  }
  t.key_told(@ui.key_escape, 0, t.time())
  t.draw()
  // (the fixture's core answers it, its mark in)
  let made = named(calls, "chat.ref")
  t.draw()
  (made.length(), desk_words(src), named(calls, "chat.send").length(), t.ctx().editor_focused(@sfpages.composer_field_key))
}

///|
test "desk composer: a chat pressed in its menu, then Escape at once: referenced once, its mark in, nothing sent, the field keeping the focus, a frame between or none" {
  let picked = (1, "看 @[首页的列表改成按天分组] ", 0, true)
  assert_eq((ref_picked_then_escape(false), ref_picked_then_escape(true)), (picked, picked))
}

///|
/// The chat chosen in the menu (↓ ↑ round to the first, frames drawn), then `key` (Enter or Tab) and Escape at once as
/// the host hands them on, a frame between or none: as ref_picked_then_escape says.
fn ref_keyed_then_escape(key : Int, frames : Bool) -> (Int, String, Int, Bool) raise {
  let calls : Array[Made] = []
  let (t, _, src) = ref_menu_tester(calls~)
  t.key(@ui.key_code_down)
  t.key(@ui.key_code_up)
  t.frame()
  t.key_told(key, 0, t.time())
  if frames {
    t.frame()
  }
  t.key_told(@ui.key_escape, 0, t.time())
  t.draw()
  let made = named(calls, "chat.ref")
  t.draw()
  (made.length(), desk_words(src), named(calls, "chat.send").length(), t.ctx().editor_focused(@sfpages.composer_field_key))
}

///|
test "desk composer: its menu of chats, Enter and Escape at once: the one chosen referenced once, its mark in, nothing sent, the field keeping the focus, a frame between or none" {
  let picked = (1, "看 @[首页的列表改成按天分组] ", 0, true)
  assert_eq((ref_keyed_then_escape(@ui.key_code_enter, false), ref_keyed_then_escape(@ui.key_code_enter, true)), (picked, picked))
}

///|
test "desk composer: its menu of chats, Tab and Escape at once: Tab puts the one chosen in (the focus staying in the field), once, a frame between or none" {
  let picked = (1, "看 @[首页的列表改成按天分组] ", 0, true)
  assert_eq((ref_keyed_then_escape(@ui.key_tab, false), ref_keyed_then_escape(@ui.key_tab, true)), (picked, picked))
}
