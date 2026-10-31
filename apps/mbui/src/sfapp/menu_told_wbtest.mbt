// The library's ⋯ menu (sf's menu_of), a message's in a chat on 大屏: dismissed by the hand (Escape, a press beside
// it) at that input's moment, and its ⋯ pressed again as it is let go; the frame after closing nothing more.

///|
/// 大屏, a mouse's, the chat open, the pointer resting on a message (its ⋯ shown).
fn message_menu_tester() -> @ui.Tester {
  new_run()
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let src = fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let (x, y, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  t.move(x + 24.0, y + 8.0)
  t.frame()
  t.frame()
  t
}

///|
/// The message's ⋯ menu opened, then dismissed by `how` (as the host hands it on, no frame after it): whether a menu
/// is open then, as it is dismissed, and once a frame is drawn.
fn message_menu_dismissed(how : (@ui.Tester) -> Unit) -> Array[Bool] raise {
  let t = message_menu_tester()
  let open = fn() { @sf.menu_open_key() != "" }
  t.click(Button, label="更多操作")
  t.run_for(@ui.move_most_ms)
  let shown = t.find("复制消息链接") is Some(_)
  let seen = [open()]
  how(t)
  seen.push(open())
  t.draw()
  seen.push(open())
  assert_true(shown, msg="its menu shown: \{seen}")
  seen
}

///|
test "大屏: a message's ⋯ menu dismissed by Escape: closed as the key is taken; the frame after closes nothing more" {
  assert_eq(message_menu_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false])
}

///|
test "大屏: a message's ⋯ menu dismissed by a press beside it: closed as it goes down; the frame after closes nothing more" {
  let down : Array[Bool] = []
  let seen = message_menu_dismissed(fn(t) {
    t.touch_at(0, 600.0, 300.0, t.time())
    down.push(@sf.menu_open_key() != "")
    t.touch_at(2, 600.0, 300.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false]))
}

///|
test "大屏: a message's ⋯ pressed again with its menu open, then Escape at once: closed as it is let go, and stays closed, a frame between or none" {
  let open = fn() { @sf.menu_open_key() != "" }
  let none = button_then_escape(message_menu_tester(), "更多操作", open, false)
  let framed = button_then_escape(message_menu_tester(), "更多操作", open, true)
  assert_eq((none, framed), ([false, false, false], [false, false, false]))
}

///|
test "大屏: a message's ⋯ menu, a key it does not take then Escape, no frame between: closed as Escape is taken" {
  let t = message_menu_tester()
  t.click(Button, label="更多操作")
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.menu_open_key() != "", msg="opened")
  t.key_told(@ui.key_code_left, 0, t.time())
  t.key_told(@ui.key_escape, 0, t.time())
  assert_eq(@sf.menu_open_key(), "")
}

///|
test "大屏: a message's ⋯ menu, two keys then a press beside it, no frame between: closed as the press goes down" {
  let t = message_menu_tester()
  t.click(Button, label="更多操作")
  t.run_for(@ui.move_most_ms)
  t.key_told(@ui.key_code_left, 0, t.time())
  t.key_told(@ui.key_code_right, 0, t.time())
  t.touch_at(0, 600.0, 300.0, t.time())
  let down = @sf.menu_open_key()
  t.touch_at(2, 600.0, 300.0, t.time())
  assert_eq(down, "")
}
