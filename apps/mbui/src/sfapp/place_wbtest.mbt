// A place gone to, one way in every tier (sfbase's shell.mbt go_place): the bottom bar's laid out Small, the rail's
// else; a chat open (laid out Small, back from it to the chats, where the bar is), then 文件 pressed: its page the
// stack's root, nothing over it; pressed again, nothing changes.

///|
test "a place gone to at each width on either screen: 文件 the stack's root from a chat open, again nothing" {
  for case in [(390.0, 2, false), (720.0, 2, false), (1280.0, 2, true), (390.0, 0, false), (720.0, 0, false), (1280.0, 0, false)] {
    let (w, platform, regular) = case
    let at = "\{w} platform \{platform}"
    let calls : Array[Made] = []
    let t = wide_tester(calls, w~, h=844.0, platform~)
    if regular {
      let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n")
      assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
    }
    t.draw()
    t.tap_text("夜里的构建又失败了")
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() is Chat(_), msg=at)
    // laid out Small the bottom bar shows on a place's root only: back to the chats' first; on the tape the chat's page
    // came over to show it, the rail in the sidebar beside it: back brings that over
    if @sfdesk.wide.tape {
      t.back()
      t.run_for(@ui.move_most_ms)
      assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side, msg=at)
    } else if t.query(Tab, label="文件") is None && t.query(Button, label="文件") is None {
      t.back()
      t.run_for(@ui.move_most_ms)
      assert_eq(app.nav.depth(), 1, msg=at)
    }
    let place = fn() raise {
      // (the bottom bar's places are its tabs, the rail's its buttons)
      let n = match t.query(Tab, label="文件") {
        Some(n) => n
        None => t.query(Button, label="文件").unwrap()
      }
      let (x, y, bw, bh) = n.rect
      t.tap(x + bw / 2.0, y + bh / 2.0)
      t.frame()
      t.run_for(@ui.move_most_ms)
    }
    place()
    assert_eq(app.nav.depth(), 1, msg=at)
    assert_true(app.nav.top() == Files, msg=at)
    place()
    assert_eq(app.nav.depth(), 1, msg=at)
    assert_true(app.nav.top() == Files, msg=at)
  }
}
