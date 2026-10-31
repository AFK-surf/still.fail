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

///|
/// The menu of chats shown, then `first` (as the host hands it on, no frame after it) and Enter at once, a frame drawn
/// once both are told: how often a chat was referenced, the words, how often a message was sent.
fn ref_then_enter(first : (@ui.Tester) -> Unit) -> (Int, String, Int) raise {
  let calls : Array[Made] = []
  let (t, _, src) = ref_menu_tester(calls~)
  first(t)
  t.key_told(@ui.key_code_enter, 0, t.time())
  t.draw()
  t.draw()
  (named(calls, "chat.ref").length(), desk_words(src), named(calls, "chat.send").length())
}

///|
test "desk composer: its menu closed by Escape, then Enter before a frame: no chat referenced from the menu it closed, Enter the field's (it sends)" {
  let (refs, words, sent) = ref_then_enter(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) })
  assert_eq((refs, sent), (0, 1), msg=words)
}

///|
test "desk composer: its menu, Enter twice before a frame: the one chosen referenced once, the second Enter the field's" {
  let (refs, words, _) = ref_then_enter(fn(t) { t.key_told(@ui.key_code_enter, 0, t.time()) })
  assert_eq(refs, 1, msg=words)
}

///|
test "desk composer: its menu, a letter typed, Enter and Escape before a frame: the one shown chosen put in for the @ and the letter, as Enter comes, the Escape after it closing nothing of it" {
  let calls : Array[Made] = []
  let (t, _, src) = ref_menu_tester(calls~)
  t.text_told("的", t.time())
  t.key_told(@ui.key_code_enter, 0, t.time())
  t.key_told(@ui.key_escape, 0, t.time())
  t.draw()
  t.draw()
  assert_eq((named(calls, "chat.ref").length(), desk_words(src), named(calls, "chat.send").length()), (1, "看 @[首页的列表改成按天分组] ", 0))
}

///|
test "desk composer: its menu under a panel that leaves the field its focus: Enter the panel's (read by it once), not the menu's nor the field's; Escape closes the panel as it is taken" {
  let calls : Array[Made] = []
  let (t, _, src) = ref_menu_tester(calls~)
  let entered = Ref(0)
  @sf.panel(
    "盖在上面",
    fn(c, _) {
      // (the keys the panel's: Enter read by it, once)
      if c.key_pressed(@ui.key_code_enter) {
        entered.val += 1
      }
      c.text("盖在上面的对话框") |> ignore
    },
    from=@sf.at_point(450.0, 60.0).anchor(),
    focus=false,
  )
  t.draw()
  assert_true(t.find("盖在上面的对话框") is Some(_))
  // (the field under it keeping the focus: what the menu is said to take keys of)
  assert_true(t.ctx().editor_focused(@sfpages.composer_field_key), msg="the field under the dialog keeps the focus")
  t.key_told(@ui.key_code_enter, 0, t.time())
  t.draw()
  assert_eq((named(calls, "chat.ref").length(), named(calls, "chat.send").length(), desk_words(src), entered.val), (0, 0, "看 @首页", 1))
  // Escape the panel's, closing it as it is taken
  t.key_told(@ui.key_escape, 0, t.time())
  assert_true(!@sf.presenting(), msg="the panel closed as Escape is taken")
}

///|
/// A finger's composer (Enter a line's end): two lines written, an `@` on the second, its menu shown, then `keys` as
/// the host hands them on, a frame between each or none: where the caret is then, and how often a chat was referenced.
fn ref_phone_then(keys : Array[Int], frames : Bool) -> (Int, Int, String) raise {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("第一行")
  t.enter()
  t.type_text("看 @首页")
  t.frame()
  let (_, words, _, _) = t.ime()
  assert_true(t.find("引用对话") is Some(_), msg=words)
  for k in keys {
    t.key_told(k, 0, t.time())
    if frames {
      t.frame()
    }
  }
  t.draw()
  let (_, words, _, caret) = t.ime()
  (caret, named(calls, "chat.ref").length(), words)
}

///|
test "a finger's composer: its menu closed by Escape, then ↑: the field's, the caret up a line, a frame between or none" {
  for frames in [false, true] {
    let (caret, refs, words) = ref_phone_then([@ui.key_escape, @ui.key_code_up], frames)
    assert_true(caret <= "第一行".length() && refs == 0, msg="(frames \{frames}) caret \{caret} in \{words}")
  }
}

///|
test "a finger's composer: a chat picked from its menu by Enter, then ↑ before a frame: the field's, the caret up a line" {
  let (caret, refs, words) = ref_phone_then([@ui.key_code_enter, @ui.key_code_up], false)
  assert_true(caret <= "第一行".length() && refs == 1, msg="caret \{caret} refs \{refs} in \{words}")
}

///|
test "desk composer: its menu for an @ with words after it: Enter puts the one chosen in for the @ and what follows it to the caret, the words after the caret as they were" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  desk_focus(t)
  t.type_text("看 @首页 后文")
  for _ in 0..<3 {
    t.key(@ui.key_code_left)
  }
  t.frame()
  t.frame()
  assert_true(t.find("引用对话") is Some(_), msg=desk_words(src))
  t.key(@ui.key_code_enter)
  t.draw()
  t.draw()
  let words = desk_words(src)
  assert_eq((named(calls, "chat.ref").length(), words.has_prefix("看 @[首页的列表改成按天分组] "), words.has_suffix(" 后文")), (1, true, true), msg=words)
}

///|
test "desk composer: its menu, `[` typed after its @ and the core's answer for it drawn (no chat): Enter is the field's, no chat referenced" {
  let calls : Array[Made] = []
  let (t, _, src) = ref_menu_tester(calls~)
  t.type_text("[")
  t.frame()
  t.frame()
  assert_true(t.find("引用对话") is None, msg=desk_words(src))
  t.key_told(@ui.key_code_enter, 0, t.time())
  t.draw()
  assert_eq(named(calls, "chat.ref").length(), 0, msg=desk_words(src))
}

///|
test "desk composer: its menu, `[` typed after its @ and Enter before a frame (its menu as it was still shown): the one shown chosen put in for the @ and what follows it" {
  let calls : Array[Made] = []
  let (t, _, src) = ref_menu_tester(calls~)
  t.text_told("[", t.time())
  t.key_told(@ui.key_code_enter, 0, t.time())
  t.draw()
  t.draw()
  assert_eq((named(calls, "chat.ref").length(), desk_words(src), named(calls, "chat.send").length()), (1, "看 @[首页的列表改成按天分组] ", 0))
}

///|
test "desk composer: its menu for an @ with words after it, the caret moved into those words and Enter before a frame: not the menu's, the words after the @ not taken as its" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  desk_focus(t)
  t.type_text("看 @首页 后文")
  for _ in 0..<3 {
    t.key(@ui.key_code_left)
  }
  t.frame()
  t.frame()
  assert_true(t.find("引用对话") is Some(_), msg=desk_words(src))
  // (into the words after it, as the host hands the keys on, no frame)
  t.key_told(@ui.key_code_right, 0, t.time())
  t.key_told(@ui.key_code_right, 0, t.time())
  t.key_told(@ui.key_code_enter, 0, t.time())
  t.draw()
  t.draw()
  assert_eq(named(calls, "chat.ref").length(), 0, msg=desk_words(src))
}

///|
test "desk composer: its menu for an @ with words after it, the caret moved into those words, then the chat shown pressed before a frame: not the menu's, the words after the @ as they were" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  desk_focus(t)
  t.type_text("看 @首页 后文")
  for _ in 0..<3 {
    t.key(@ui.key_code_left)
  }
  t.frame()
  t.frame()
  assert_true(t.find("引用对话") is Some(_), msg=desk_words(src))
  let (cx, cy, cw, ch) = t.rect_of("首页的列表改成按天分组").unwrap()
  t.key_told(@ui.key_code_right, 0, t.time())
  t.key_told(@ui.key_code_right, 0, t.time())
  t.touch_at(0, cx + cw / 2.0, cy + ch / 2.0, t.time())
  t.touch_at(2, cx + cw / 2.0, cy + ch / 2.0, t.time())
  t.draw()
  t.draw()
  assert_eq((named(calls, "chat.ref").length(), desk_words(src)), (0, "看 @首页 后文"))
}
