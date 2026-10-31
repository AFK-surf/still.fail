// A right click's menu in a chat on 大屏 (sfdesk's context_menu.mbt: a message's turn, a field's editing, the words picked)
// dismissed by the hand: Escape, a press on the page, at that input's moment; the frame after closing nothing more,
// a right click opening it again its own.

///|
/// 大屏, a mouse's, the chat open, scrolled till Ana's message shows: its words right clicked (its menu, 分享这一轮
/// and what else there is), dismissed by `how` (as the host hands it on, no frame after it): whether it is open then, once a
/// frame is drawn, as a right click opens it again and a frame after.
fn context_dismissed(how : (@ui.Tester) -> Unit) -> Array[Bool] raise {
  let t = wide_tester([], mode="chat")
  for _ in 0..<12 {
    match t.run_rects("example.com/review/42") {
      [(_, y, _, _), ..] if y > 100.0 && y < 600.0 => break
      _ => t.wheel(900.0, 400.0, -200.0)
    }
  }
  let (x, y, w, h) = words_rect(t, "第二屏的插画")
  let open = fn() { @sfdesk.context.open }
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.frame()
  let shown = t.find("分享这一轮") is Some(_)
  let seen = [open()]
  how(t)
  seen.push(open())
  t.draw()
  seen.push(open())
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.frame()
  seen.push(open())
  t.draw()
  seen.push(open())
  assert_true(shown, msg="its menu shown: \{seen}")
  seen
}

///|
test "大屏: a right click's menu in a chat dismissed by Escape: closed as the key is taken; the frame after closes nothing more, opened again its own" {
  assert_eq(context_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false, true, true])
}

///|
test "大屏: a right click's menu in a chat dismissed by a press beside it: closed as it goes down; the frame after closes nothing more, opened again its own" {
  let down : Array[Bool] = []
  let seen = context_dismissed(fn(t) {
    t.touch_at(0, 600.0, 300.0, t.time())
    down.push(@sfdesk.context.open)
    t.touch_at(2, 600.0, 300.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false, true, true]))
}
