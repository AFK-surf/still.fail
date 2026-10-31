// The ＋ over the workspaces on 大屏 (sfpages' workspace.mbt: its menu, 新建 workspace, 添加另一个账号, the invitations)
// dismissed by the hand: Escape, a press on the page, at that input's moment; the ＋ pressed again with it open, then
// Escape at once, closed and staying closed.

///|
/// 大屏, a mouse's: the ＋'s menu opened, dismissed by `how` (as the host hands it on, no frame after it): whether it is
/// open then, once a frame is drawn, as the ＋ opens it again and a frame after.
fn ws_menu_dismissed(how : (@ui.Tester) -> Unit) -> Array[Bool] raise {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  t.draw()
  guard t.query(Button, label="新建 workspace、添加账号") is Some(s) else { fail("no ＋") }
  let (x, y) = (s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0)
  t.tap(x, y)
  t.frame()
  let seen = [@sfpages.workspace_menu_open()]
  how(t)
  seen.push(@sfpages.workspace_menu_open())
  t.draw()
  seen.push(@sfpages.workspace_menu_open())
  t.tap(x, y)
  t.frame()
  seen.push(@sfpages.workspace_menu_open())
  t.draw()
  seen.push(@sfpages.workspace_menu_open())
  seen
}

///|
test "大屏: the ＋'s menu dismissed by Escape: closed as the key is taken; the frame after closes nothing more, opened again its own" {
  assert_eq(ws_menu_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false, true, true])
}

///|
test "大屏: the ＋'s menu dismissed by a press on the page: closed as it goes down; the frame after closes nothing more, opened again its own" {
  let down : Array[Bool] = []
  let seen = ws_menu_dismissed(fn(t) {
    t.touch_at(0, 900.0, 300.0, t.time())
    down.push(@sfpages.workspace_menu_open())
    t.touch_at(2, 900.0, 300.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false, true, true]))
}

///|
test "大屏: the ＋ pressed again with its menu open, then Escape at once: closed as it is let go, and stays closed, a frame between or none" {
  let run = fn(frames : Bool) raise {
    button_then_escape(wide_tester([]), "新建 workspace、添加账号", fn() { @sfpages.workspace_menu_open() }, frames)
  }
  assert_eq((run(false), run(true)), ([false, false, false], [false, false, false]))
}
