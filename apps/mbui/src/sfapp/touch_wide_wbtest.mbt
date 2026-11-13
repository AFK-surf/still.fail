// The wide frame on a tablet's screen (an opened fold's inner one: the system's size classes regular both ways), pointed
// at with a finger: the desktop's layout, the finger's hand (@ui.pointing).

///|
fn touch_wide_tester() -> @ui.Tester raise {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=860.0, h=950.0, platform=2)
  let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\nuntil 发消息\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  t
}

///|
test "touch wide: the desktop's frame, a chat's row held opens its menu (no right click there), the chat not opened" {
  let t = touch_wide_tester()
  assert_true(@sfdesk.is_wide(t.ctx()))
  let log = t.drive("hold 700 首页的列表改成按天分组\nuntil 分享…\nuntil 归档\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  assert_true(
    match app.nav.top() {
      Chat(r) => r.session == "s-c1"
      _ => false
    },
  )
}

///|
test "touch wide: a row tapped is opened and left as it rests (a lifted finger hovers over nothing: no 归档 key on it)" {
  let t = touch_wide_tester()
  let log = t.drive("tap 首页的列表改成按天分组\nuntil 好的，我来处理\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  t.draw()
  assert_true(t.query(Button, label="归档「首页的列表改成按天分组」") is None)
}

///|
test "touch wide: a row held shows its time while its menu is open, its 归档 in the menu, not on the row" {
  let t = touch_wide_tester()
  let log = t.drive("hold 700 首页的列表改成按天分组\nuntil 分享…\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  assert_true(t.find("8 分钟前") is Some(_))
  assert_true(t.query(Button, label="归档「首页的列表改成按天分组」") is None)
  // under the row, not over it
  let (_, row_y) = t.find("首页的列表改成按天分组").unwrap()
  let (_, time_y) = t.find("8 分钟前").unwrap()
  let (_, menu_y) = t.find("重命名").unwrap()
  assert_true(menu_y > time_y && time_y > row_y)
}

///|
/// The fixture's chat on the narrowest tablet held upright (600 × 900, regular both ways): beside the sidebar less than a
/// phone's width (@sfdesk.page_beside_least).
fn touch_narrow_tester() -> @ui.Tester raise {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=600.0, h=900.0, platform=2)
  // (the tape's sidebar in use at first, a strip of the chat beside it)
  let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\nuntil 新建对话\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "touch wide, a small tablet held upright (600 wide, its system saying regular): by its width the tape, nothing folded for room" {
  let t = touch_narrow_tester()
  assert_true(@sfdesk.is_wide(t.ctx()))
  assert_true(@sfdesk.wide.tape.get())
  assert_false(@sfdesk.wide.crowded)
}

///|
test "touch wide: a message's words held, the passage's handles at its ends in the pane beside the sidebar, the bar over it" {
  let t = touch_wide_tester()
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  t.draw()
  // the handles, as this frame painted them where a finger takes each, on whichever page the chat is made
  // (Tester::picking: x at the passage's start and at its end, y on or by their lines)
  guard t.picking() is Some(p) &&
    p.finger &&
    p.ends.get(0) is Some(Some((sx, sy))) &&
    p.ends.get(1) is Some(Some((lx, ly))) else {
    fail("no handles over what the finger picked: \{Repr(t.picking())}")
  }
  // the passage's ground (translucent, a line's height) from the start's handle to the end's, on their lines, in the
  // pane beside the sidebar: what the handles stand at its ends of
  let grounds = t.drawn_rects().filter(fn(r) { (r.4 & 0xFFL) < 0xFFL && r.3 > 8.0 && r.3 < 60.0 })
  let near = fn(r : (Double, Double, Double, Double, Int64), y : Double) { y > r.1 - 30.0 && y < r.1 + r.3 + 30.0 }
  let starts = grounds.filter(fn(r) { (r.0 - sx).abs() < 1.5 && near(r, sy) })
  let ends = grounds.filter(fn(r) { (r.0 + r.2 - lx).abs() < 1.5 && near(r, ly) })
  assert_true(starts.length() > 0, msg="start's handle at \{sx},\{sy}, no passage starting there")
  assert_true(ends.length() > 0, msg="end's handle at \{lx},\{ly}, no passage ending there")
  let (_, py, _, _, _) = starts[0]
  // the bar over the passage: its 引用 drawn over it, or the system's text menu over it offering 引用
  let menu = t.text_menu()
  match t.find("引用") {
    Some((_, quote_y)) => assert_true(quote_y < py && quote_y > py - 60.0, msg="引用 at \{quote_y}, passage at \{py}")
    None => {
      assert_true(menu.0 && t.text_menu_own().contains("引用"), msg="no bar with 引用 over the passage: \{Repr(menu)}")
      assert_true(menu.2 <= py + 1.5 && menu.2 + menu.4 >= py, msg="the menu over \{Repr(menu)}, passage at \{py}")
    }
  }
}

///|
test "touch wide: the sidebar drawn on its own ground, a step under the page's beige, the panes told apart" {
  let t = touch_wide_tester()
  let p = @sf.theme().p
  assert_true(p.sidebar != p.bg)
  let grounds = t.drawn_rects().map(fn(r) { r.4 })
  assert_true(grounds.contains(p.sidebar), msg="no rect on the sidebar's ground")
  assert_true(grounds.contains(p.bg), msg="no rect on the page's ground")
}
