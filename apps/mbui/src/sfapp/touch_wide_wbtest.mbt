// The wide frame on a tablet's screen (an opened fold's inner one: the system's size classes regular both ways), pointed
// at with a finger: the desktop's layout, the finger's hand (@ui.pointing).

///|
fn touch_wide_tester() -> @ui.Tester raise {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=860.0, h=950.0, platform=2)
  let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\nuntil 发消息\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  t
}

///|
test "touch wide: the desktop's frame, a chat's row held opens its menu (no right click there), the chat not opened" {
  let t = touch_wide_tester()
  assert_true(wide_on.val)
  let log = t.drive("hold 700 首页的列表改成按天分组\nuntil 复制会话链接\nuntil 归档\n")
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
  let log = t.drive("hold 700 首页的列表改成按天分组\nuntil 复制会话链接\n")
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
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=600.0, h=900.0, platform=2)
  let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\nuntil 发消息\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  t.run_for(@sfdesk.side_move_ms)
  t
}

///|
/// The rail's place `label` tapped, the sidebar's move run.
fn tap_place(t : @ui.Tester, label : String) -> Unit raise {
  let (x, y, w, h) = t.query(Button, label~).unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@sfdesk.side_move_ms)
}

///|
test "touch wide, a small tablet held upright: the chats' list folded to the rail for the page's room, what was chosen kept; its place tapped shows it over the page, a chat chosen there opens and folds it, a tap on the page folds it" {
  let t = touch_narrow_tester()
  assert_true(wide_on.val)
  assert_true(@sfdesk.wide.crowded)
  assert_false(@sfdesk.wide.folded)
  // the page from the rail's bar on: no row of the list, the chat's words where the list would be
  assert_true(t.find("夜里的构建又失败了") is None, msg=t.drawn_text())
  let (cx, _, _, _) = words_at(t, "做完了：列表").unwrap()
  assert_true(cx < @sfdesk.rail_w + 240.0, msg="the chat's words at \{cx}")
  // its place tapped: shown over the page
  tap_place(t, "对话")
  assert_true(@sfdesk.wide.peeking)
  assert_true(t.find("夜里的构建又失败了") is Some(_), msg=t.drawn_text())
  // a chat chosen there: opened, the list folded again
  t.tap_text("首页的列表改成按天分组")
  t.run_for(@sfdesk.side_move_ms)
  match app.nav.top() {
    Chat(r) => assert_true(r.session != "s-c1", msg="still \{r.session}")
    _ => fail("not a chat")
  }
  assert_false(@sfdesk.wide.peeking)
  // (another chat's row: the one chosen is the page's title now)
  assert_true(t.find("夜里的构建又失败了") is None)
  // shown again, its place tapped again: folded; shown, a tap on the page: folded
  tap_place(t, "对话")
  assert_true(@sfdesk.wide.peeking)
  tap_place(t, "对话")
  assert_false(@sfdesk.wide.peeking)
  tap_place(t, "对话")
  t.tap(560.0, 450.0)
  t.run_for(@sfdesk.side_move_ms)
  assert_false(@sfdesk.wide.peeking)
  // nothing of it kept as the person's (prefs.set sidebars): turned, the list beside the page again
  assert_false(@sfdesk.wide.folded)
}

///|
test "touch wide, a small tablet held upright: another place tapped (设置) is gone to with its list shown over the page; a page of it chosen there folds it" {
  let t = touch_narrow_tester()
  tap_place(t, "设置")
  assert_true(@sfdesk.wide.crowded)
  assert_true(@sfdesk.wide.peeking, msg=t.drawn_text())
  t.tap_text("关于")
  t.run_for(@sfdesk.side_move_ms)
  assert_false(@sfdesk.wide.peeking)
}

///|
test "touch wide: a message's words held, the passage's handles at its ends in the pane beside the sidebar, the bar over it" {
  let t = touch_wide_tester()
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  t.draw()
  assert_true(pk.ts != "")
  let accent = @sf.theme().p.accent
  let ground = @sf.alpha(accent, 0.26)
  let passage = t.drawn_rects().filter(fn(r) { r.4 == ground })
  assert_true(passage.length() > 0, msg=t.drawn_text())
  let (px, py, pw, ph, _) = passage[0]
  let (ex, ey, ew, eh, _) = passage[passage.length() - 1]
  // the handles' lines (2 wide, the accent): down the passage's first line's start and its last line's end
  let lines = t.drawn_rects().filter(fn(r) { r.4 == accent && r.2 < 3.0 })
  assert_eq(lines.length(), 2)
  let (sx, sy, sw, _, _) = lines[0]
  let (lx, ly, lw, _, _) = lines[1]
  assert_true((sx + sw / 2.0 - px).abs() < 1.5 && (sy - py).abs() < 1.5, msg="start at \{sx},\{sy}, passage at \{px},\{py},\{pw},\{ph}")
  assert_true((lx + lw / 2.0 - (ex + ew)).abs() < 1.5 && (ly - ey).abs() < 1.5, msg="end at \{lx},\{ly}, passage's end at \{ex + ew},\{ey},\{eh}")
  // the bar over the passage
  let (_, quote_y) = t.find("引用").unwrap()
  assert_true(quote_y < py && quote_y > py - 60.0, msg="引用 at \{quote_y}, passage at \{py}")
}
