// A menu of the presenters' (@sf.menu) on 中屏 and 大屏 as nodes of the window's tree (menu_node): beside what opened it
// (under it, over it where there is not the room under), its items chosen by a press, by the keyboard (Up and Down
// along them past what cannot be chosen, Enter) and by letters typed; what it holds scrolling where it is taller than
// the window leaves it. On 小屏 a sheet still, the old frame's.

///|
/// `w` by `h`, started as `platform` (0 macOS: keyboard and mouse; 2 Android: touch), chat A open, drawn.
fn menu_tester(w : Double, h : Double, platform : Int) -> @ui.Tester {
  new_run()
  let src = fixture("chat")
  wide_src.val = Some(src)
  open_chat(chat_a)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Items `labels` (`off` the indices not to be chosen now), each counting into `chosen` by its index as chosen.
fn menu_items_counting(labels : Array[String], chosen : Array[Int], off? : Array[Int] = []) -> Array[@sf.MenuItem?] {
  labels.mapi(fn(i, l) {
    Some({ label: l, icon: "", danger: false, disabled: off.contains(i), chosen: None, heading: false, select: fn() { chosen.push(i) } })
  })
}

///|
test "大屏, keyboard and mouse: a menu presented at a point: drawn by the window's tree, its panel under the point; an item pressed: chosen once, the menu closed" {
  let t = menu_tester(1280.0, 800.0, 0)
  let chosen = []
  @sf.menu(menu_items_counting(["复制", "重命名", "删除"], chosen), from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  let tree_menu = tree_said(Menu, "") is Some(_)
  let (_, py, _, _) = t.query(Menu).unwrap().rect
  let (x, y, w, h) = t.query(MenuItem, label="重命名").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq((tree_menu, py >= 300.0, chosen, @sf.presenting(), t.query(Menu) is None), (true, true, [1], false, true))
}

///|
test "大屏, keyboard and mouse: a menu presented, nothing lit: Down to its first, Down past one not to be chosen, Enter: that one chosen" {
  let t = menu_tester(1280.0, 800.0, 0)
  let chosen = []
  @sf.menu(menu_items_counting(["复制", "重命名", "删除"], chosen, off=[1]), from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_code_down)
  t.key(@ui.key_code_down)
  t.key(@ui.key_code_enter)
  t.run_for(@ui.move_most_ms)
  assert_eq((chosen, @sf.presenting()), ([2], false))
}

///|
test "大屏, keyboard and mouse: a menu presented, letters typed: b to the first that starts with it, b again to the next, Enter: that one chosen" {
  let t = menu_tester(1280.0, 800.0, 0)
  let chosen = []
  @sf.menu(menu_items_counting(["apple", "banana", "blueberry", "cherry"], chosen), from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_of_char('b'))
  t.key(@ui.key_of_char('b'))
  t.key(@ui.key_code_enter)
  t.run_for(@ui.move_most_ms)
  assert_eq(chosen, [2])
}

///|
test "大屏, keyboard and mouse: a menu presented at a point near the window's foot: its panel over the point, all of it in the window" {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.menu(menu_items_counting(["复制", "重命名", "删除"], []), from=@sf.at_point(600.0, 780.0))
  t.run_for(@ui.move_most_ms)
  let (_, py, _, ph) = t.query(Menu).unwrap().rect
  assert_eq((py + ph <= 780.0 + 0.5, py >= 0.0), (true, true), msg="panel \{py} \{ph}")
}

///|
test "大屏, keyboard and mouse, a short window: a menu taller than it: its panel in the window; the wheel over it: its last item brought into sight in it" {
  let t = menu_tester(1280.0, 340.0, 0)
  let labels = Array::makei(30, fn(i) { "第\{i}项" })
  @sf.menu(menu_items_counting(labels, []), from=@sf.at_point(600.0, 40.0))
  t.run_for(@ui.move_most_ms)
  let (px, py, pw, ph) = t.query(Menu).unwrap().rect
  let within = py >= 0.0 && py + ph <= 340.0 + 0.5
  for _ in 0..<20 {
    t.wheel(px + pw / 2.0, py + ph / 2.0, 120.0)
    t.run_for(@ui.move_most_ms)
  }
  let last = t.rect_of("第29项")
  let seen = match last {
    Some((_, y, _, h)) => y >= py - 0.5 && y + h <= py + ph + 0.5
    None => false
  }
  assert_eq((within, seen), (true, true), msg="panel \{(px, py, pw, ph)} last \{last}")
}

///|
test "小屏: a menu presented: a sheet still, the old frame's, nothing of it the window's tree's" {
  let t = menu_tester(390.0, 844.0, 2)
  @sf.menu(menu_items_counting(["复制", "重命名", "删除"], []), from=@sf.at_point(200.0, 300.0))
  t.run_for(@ui.move_most_ms)
  assert_eq((tree_said(Menu, "") is None, t.find("重命名") is Some(_)), (true, true))
}

///|
test "大屏, keyboard and mouse, a short window: a menu taller than it, the pointer resting on one of its items, then End, the pointer not moved: the focus on its last item, not the one come under the pointer, that item in sight in its panel; Enter: it chosen, once" {
  let t = menu_tester(1280.0, 340.0, 0)
  let chosen = []
  let labels = Array::makei(30, fn(i) { "第\{i}项" })
  @sf.menu(menu_items_counting(labels, chosen), from=@sf.at_point(600.0, 40.0))
  t.run_for(@ui.move_most_ms)
  // (the pointer brought onto its third item, and left there)
  let (rx, ry, rw, rh) = t.query(MenuItem, label="第2项").unwrap().rect
  t.move(rx + rw / 2.0, ry + rh / 2.0)
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_code_end)
  t.run_for(@ui.move_most_ms)
  let focused = t.focused().map(fn(s) { s.label })
  let (_, py, _, ph) = t.query(Menu).unwrap().rect
  let last = t.rect_of("第29项")
  let seen = match last {
    Some((_, y, _, h)) => y >= py - 0.5 && y + h <= py + ph + 0.5
    None => false
  }
  t.key(@ui.key_code_enter)
  t.key(@ui.key_code_enter)
  t.run_for(@ui.move_most_ms)
  assert_eq((focused, seen, chosen), (Some("第29项"), true, [29]), msg="panel \{py} \{ph} last \{last}")
}

///|
test "大屏, keyboard and mouse: a menu with a heading, a line and an item not to be chosen: a press on its heading, on that item and on its padding, nothing chosen, the menu open; a press outside it: closed as it goes down" {
  let t = menu_tester(1280.0, 800.0, 0)
  let chosen = []
  let items : Array[@sf.MenuItem?] = [
    Some({ label: "一组", icon: "", danger: false, disabled: false, chosen: None, heading: true, select: fn() { chosen.push(-1) } }),
    Some({ label: "复制", icon: "", danger: false, disabled: false, chosen: None, heading: false, select: fn() { chosen.push(0) } }),
    None,
    Some({ label: "删除", icon: "", danger: true, disabled: true, chosen: None, heading: false, select: fn() { chosen.push(1) } }),
  ]
  @sf.menu(items, from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  let press = fn(r : (Double, Double, Double, Double)) {
    t.tap(r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
    t.run_for(@ui.move_most_ms)
  }
  press(t.rect_of("一组").unwrap())
  press(t.rect_of("删除").unwrap())
  let (px, py, pw, ph) = t.query(Menu).unwrap().rect
  // (its padding, under its last item)
  t.tap(px + pw / 2.0, py + ph - 2.0)
  t.run_for(@ui.move_most_ms)
  let open_still = @sf.presenting()
  t.touch_at(0, 1100.0, 150.0, t.time())
  let closed_down = !@sf.presenting()
  t.touch_at(2, 1100.0, 150.0, t.time())
  t.run_for(@ui.move_most_ms)
  assert_eq((chosen, open_still, closed_down), ([], true, true))
}

///|
test "大屏, touch: the chat's message field typed in, a menu presented over it: the field's focus and keyboard left in place, what is typed its; closed by a press outside: the field's still, nothing of it lost, the menu not opened again" {
  let t = menu_tester(1280.0, 800.0, 2)
  let said = fn() { t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none") }
  t.tap_text("发消息")
  t.run_for(@ui.move_most_ms)
  t.type_text("改")
  t.run_for(@ui.move_most_ms)
  @sf.menu(menu_items_counting(["一项", "二项"], []), from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  let (keyboard, words, _, _) = t.ime()
  let open = (said(), keyboard, words, @sf.presenting())
  t.type_text("好")
  t.run_for(@ui.move_most_ms)
  t.tap(1100.0, 150.0)
  t.run_for(@ui.move_most_ms)
  let (keyboard, words, _, _) = t.ime()
  let closed = (said(), keyboard, words, @sf.presenting())
  t.run_for(@ui.move_most_ms)
  assert_eq(
    (open, closed, @sf.presenting()),
    (("TextField 发消息", true, "改", true), ("TextField 发消息", true, "改好", false), false),
  )
}

///|
test "大屏, keyboard and mouse, a short window: a menu taller than it, the pointer resting on one of its items, End, then the pointer moved a little within the item come under it: the focus on that item, not the last; Enter: that one chosen, once" {
  let t = menu_tester(1280.0, 340.0, 0)
  let chosen = []
  let labels = Array::makei(30, fn(i) { "第\{i}项" })
  @sf.menu(menu_items_counting(labels, chosen), from=@sf.at_point(600.0, 40.0))
  t.run_for(@ui.move_most_ms)
  let (rx, ry, rw, rh) = t.query(MenuItem, label="第2项").unwrap().rect
  let (x, y) = (rx + rw / 2.0, ry + rh / 2.0)
  t.move(x, y)
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_code_end)
  t.run_for(@ui.move_most_ms)
  let after_end = t.focused().map(fn(s) { s.label })
  // (what has come under the pointer as it scrolled: moved within it)
  let under = t
    .all(MenuItem)
    .iter()
    .find_first(fn(s) {
      let (sx, sy, sw, sh) = s.rect
      x + 3.0 >= sx && x + 3.0 < sx + sw && y >= sy && y < sy + sh
    })
    .map(fn(s) { s.label })
  t.move(x + 3.0, y)
  t.run_for(@ui.move_most_ms)
  let moved = t.focused().map(fn(s) { s.label })
  t.key(@ui.key_code_enter)
  t.key(@ui.key_code_enter)
  t.run_for(@ui.move_most_ms)
  let want = labels.search(under.unwrap_or("")).unwrap_or(-1)
  assert_eq(
    (after_end, under != Some("第29项") && under is Some(_), moved == under, chosen),
    (Some("第29项"), true, true, [want]),
    msg="under \{under} moved \{moved}",
  )
}

///|
test "大屏, touch: the chat's message field typed in, a menu presented over it: Enter sends nothing, the menu open; the wheel over the chat beside it scrolls nothing; Escape closes the menu alone, the field's focus, keyboard and words kept" {
  let t = menu_tester(1280.0, 800.0, 2)
  let said = fn() { t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none") }
  t.tap_text("发消息")
  t.run_for(@ui.move_most_ms)
  t.type_text("改好")
  t.run_for(@ui.move_most_ms)
  @sf.menu(menu_items_counting(["一项", "二项"], []), from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  t.enter()
  t.run_for(@ui.move_most_ms)
  let (_, words, _, _) = t.ime()
  let entered = (said(), words, @sf.presenting())
  let at = fn() { t.rect_of("做完了：列表、跳到最新的按钮").map(fn(r) { r.1 }) }
  let y0 = at()
  t.wheel(900.0, 500.0, -300.0)
  t.run_for(@ui.move_most_ms)
  let wheeled = (at() == y0, @sf.presenting())
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  let (keyboard, words, _, _) = t.ime()
  let escaped = (said(), keyboard, words, @sf.presenting())
  assert_eq(
    (entered, wheeled, escaped),
    (("TextField 发消息", "改好", true), (true, true), ("TextField 发消息", true, "改好", false)),
  )
}

///|
/// 大屏 started with touch, chat A open, its message field typed in (改好), a menu of 一项 and 二项 presented at a point
/// over it.
fn menu_over_typed_field() -> @ui.Tester {
  let t = menu_tester(1280.0, 800.0, 2)
  t.tap_text("发消息")
  t.run_for(@ui.move_most_ms)
  t.type_text("改好")
  t.run_for(@ui.move_most_ms)
  @sf.menu(menu_items_counting(["一项", "二项"], []), from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// What has the focus, whether the keyboard is up, the field's words, and whether a menu is open.
fn menu_field_said(t : @ui.Tester) -> String {
  let f = t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none")
  let (k, w, _, _) = t.ime()
  "\{f} ime=\{k} words=\{w} open=\{@sf.presenting()}"
}

///|
test "大屏, touch: a menu presented over the message field typed in, a finger then moved onto one of its items, Escape or Enter; or Down, then a letter's key: the focus, the keyboard and the words the field's throughout, Enter choosing nothing, Escape closing the menu, as the old menu" {
  let t = menu_over_typed_field()
  let (x, y) = t.find("二项").unwrap()
  t.move(x, y)
  t.run_for(@ui.move_most_ms)
  let a_on = menu_field_said(t)
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  let a_esc = menu_field_said(t)
  let t = menu_over_typed_field()
  let (x, y) = t.find("二项").unwrap()
  t.move(x, y)
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_code_enter)
  t.run_for(@ui.move_most_ms)
  let b_enter = menu_field_said(t)
  let t = menu_over_typed_field()
  t.key(@ui.key_code_down)
  t.run_for(@ui.move_most_ms)
  let c_down = menu_field_said(t)
  t.key(@ui.key_of_char('e'))
  t.run_for(@ui.move_most_ms)
  let c_letter = menu_field_said(t)
  let kept = "TextField 发消息 ime=true words=改好"
  assert_eq(
    [a_on, a_esc, b_enter, c_down, c_letter],
    [kept + " open=true", kept + " open=false", kept + " open=true", kept + " open=true", kept + " open=true"],
  )
}

///|
test "大屏, touch: a menu presented over the message field typed in, then a mouse onto one of its items: the focus on that item, the keyboard away; Escape: closed, the focus, the keyboard and the words the field's again; Enter instead: that item chosen, the field's again; or a finger's tap on another: it chosen, the field's again, as the old menu" {
  let chosen = []
  let open_over = fn() {
    let t = menu_tester(1280.0, 800.0, 2)
    t.tap_text("发消息")
    t.run_for(@ui.move_most_ms)
    t.type_text("改好")
    t.run_for(@ui.move_most_ms)
    @sf.menu(menu_items_counting(["一项", "二项"], chosen), from=@sf.at_point(600.0, 300.0))
    t.run_for(@ui.move_most_ms)
    t
  }
  let onto = fn(t : @ui.Tester) {
    t.host_says_finger(Some(false))
    let (x, y) = t.find("二项").unwrap()
    t.move(x - 10.0, y)
    t.run_for(@ui.move_most_ms)
    t.move(x, y)
    t.run_for(@ui.move_most_ms)
  }
  let t = open_over()
  onto(t)
  let a_on = menu_field_said(t)
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  let a_esc = menu_field_said(t)
  let t = open_over()
  onto(t)
  t.key(@ui.key_code_enter)
  t.run_for(@ui.move_most_ms)
  let b_enter = menu_field_said(t)
  let t = open_over()
  t.tap_text("一项")
  t.run_for(@ui.move_most_ms)
  let d_tap = menu_field_said(t)
  let field = "TextField 发消息 ime=true words=改好 open=false"
  assert_eq(
    ([a_on, a_esc, b_enter, d_tap], chosen),
    (["MenuItem 二项 ime=false words= open=true", field, field, field], [1, 0]),
  )
}

///|
/// 大屏 started with keyboard and mouse, chat A open, a menu of 一项, 二项 and 三项 presented at a point (each counting
/// into `chosen`).
fn menu_of_three(chosen : Array[Int]) -> @ui.Tester {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.menu(menu_items_counting(["一项", "二项", "三项"], chosen), from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// What has the focus (a menu by its role alone), whether a menu is open, and what was chosen.
fn menu_keys_said(t : @ui.Tester, chosen : Array[Int]) -> String {
  let f = t.focused().map(fn(s) { if s.role is Menu { "Menu" } else { "\{s.role} \{s.label}" } }).unwrap_or("none")
  "\{f} open=\{@sf.presenting()} chosen=\{chosen}"
}

///|
test "大屏, keyboard and mouse: a menu presented, Down to its first item, then with Ctrl, Cmd, Alt or Shift held Down and Enter: nothing moved, nothing chosen; Escape with it held: closed, the message field's focus back, as the old menu" {
  let out = []
  for m in [@ui.mod_ctrl, @ui.mod_cmd, @ui.mod_alt, @ui.mod_shift_key] {
    let chosen = []
    let t = menu_of_three(chosen)
    t.key(@ui.key_code_down)
    t.run_for(@ui.move_most_ms)
    t.key(@ui.key_code_down, mods=m)
    t.run_for(@ui.move_most_ms)
    let down = menu_keys_said(t, chosen)
    t.key(@ui.key_code_enter, mods=m)
    t.run_for(@ui.move_most_ms)
    let enter = menu_keys_said(t, chosen)
    t.key(@ui.key_escape, mods=m)
    t.run_for(@ui.move_most_ms)
    out.push((down, enter, menu_keys_said(t, chosen)))
  }
  let held = ("MenuItem 一项 open=true chosen=[]", "MenuItem 一项 open=true chosen=[]", "TextField 发消息 open=false chosen=[]")
  assert_eq(out, [held, held, held, held])
}

///|
test "大屏, keyboard and mouse: a menu presented, Tab or Shift+Tab from its panel: to its first item; from an item, Tab or Shift+Tab: to its panel, as the old menu (its panel and its items two stops of Tab's)" {
  let out = []
  for from_row in [false, true] {
    for shift in [false, true] {
      let chosen = []
      let t = menu_of_three(chosen)
      if from_row {
        t.key(@ui.key_code_down)
        t.run_for(@ui.move_most_ms)
      }
      let before = menu_keys_said(t, chosen)
      t.key(@ui.key_tab, mods=if shift { @ui.mod_shift_key } else { 0 })
      t.run_for(@ui.move_most_ms)
      out.push((before, menu_keys_said(t, chosen)))
    }
  }
  let panel = "Menu open=true chosen=[]"
  let row = "MenuItem 一项 open=true chosen=[]"
  assert_eq(out, [(panel, row), (panel, row), (row, panel), (row, panel)])
}

///|
test "大屏, keyboard and mouse: a menu's items given anew as it is open (one, then three, the second not to be chosen, as a row's menu as what is chosen comes): its rows as they are now, its focus and its way in as they were; Down twice past the one not to be chosen, Enter: the one lit done, of the new" {
  let t = menu_tester(1280.0, 800.0, 0)
  let done : Array[String] = []
  // (kept where the page keeps it, as drive_row_menu keeps a row's)
  let held : Array[@sf.MenuItem?] = [menu_item_doing("下载", done)]
  @sf.menu(held, from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  let before = t.focused().map(fn(s) { s.role is Menu })
  // (given anew whole, then told, as drive_row_menu_now does)
  held.clear()
  held.push_iter([menu_item_doing("下载 2 个文件", done), menu_item_doing("复制路径", done, off=true), menu_item_doing("删除 2 项", done)].iter())
  @sf.presented_changed()
  t.frame()
  let rows = t.all(MenuItem).map(fn(s) { s.label })
  // (its words as far in as they were: its way in not begun again)
  let tree = @ui.view_tree().unwrap()
  let shown = tree.drawn().filter(fn(d) { d.words == "下载 2 个文件" }).map(fn(d) { d.alpha })
  let after = t.focused().map(fn(s) { s.role is Menu })
  t.key(@ui.key_code_down)
  t.key(@ui.key_code_down)
  let lit = t.focused().map(fn(s) { s.label })
  t.key(@ui.key_code_enter)
  t.run_for(@ui.move_most_ms)
  assert_eq(
    (before, rows, shown, after, lit, done, @sf.presenting()),
    (Some(true), ["下载 2 个文件", "复制路径", "删除 2 项"], [1.0], Some(true), Some("删除 2 项"), ["删除 2 项"], false),
  )
}

///|
test "大屏, keyboard and mouse: a menu's row made one not to be chosen as it is open, the pointer on it: pressed, nothing done; made one again, pressed: its own done" {
  let t = menu_tester(1280.0, 800.0, 0)
  let done : Array[String] = []
  let held : Array[@sf.MenuItem?] = [menu_item_doing("复制", done), menu_item_doing("移动", done)]
  @sf.menu(held, from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  held[1] = menu_item_doing("移动", done, off=true)
  @sf.presented_changed()
  t.frame()
  let (x, y, w, h) = t.get(MenuItem, label="移动").rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.frame()
  let off_pressed = (done.copy(), @sf.presenting())
  // (not to be chosen: pressed, nothing done, still open)
  assert_eq(off_pressed, ([], true))
  held[1] = menu_item_doing("移到废纸篓", done)
  @sf.presented_changed()
  t.frame()
  let (x, y, w, h) = t.get(MenuItem, label="移到废纸篓").rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq((off_pressed, done, @sf.presenting()), (([], true), ["移到废纸篓"], false))
}

///|
test "大屏, keyboard and mouse: a menu's row lit, Tab to its panel, then that row made one not to be chosen, taken out or made a heading as it is open: Tab from the panel to the first that can be chosen; Enter: that one done" {
  let out = []
  for change in ["off", "gone", "heading"] {
    let t = menu_tester(1280.0, 800.0, 0)
    let done : Array[String] = []
    let held : Array[@sf.MenuItem?] = [menu_item_doing("一项", done), menu_item_doing("二项", done), menu_item_doing("三项", done)]
    @sf.menu(held, from=@sf.at_point(600.0, 300.0))
    t.run_for(@ui.move_most_ms)
    t.key(@ui.key_code_down)
    t.key(@ui.key_code_down)
    let lit = t.focused().map(fn(s) { s.label })
    t.key(@ui.key_tab)
    let panel = t.focused().map(fn(s) { s.role is Menu })
    let now : Array[@sf.MenuItem?] = match change {
      "off" => [menu_item_doing("一项", done), menu_item_doing("二项", done, off=true), menu_item_doing("三项", done)]
      "gone" => [menu_item_doing("一项", done)]
      _ => [menu_item_doing("一项", done), menu_item_doing("二项", done, heading=true), menu_item_doing("三项", done)]
    }
    held.clear()
    held.push_iter(now.iter())
    @sf.presented_changed()
    t.frame()
    t.key(@ui.key_tab)
    let tabbed = t.focused().map(fn(s) { s.label })
    t.key(@ui.key_code_enter)
    t.run_for(@ui.move_most_ms)
    out.push((change, lit, panel, tabbed, done))
  }
  assert_eq(out, [
    ("off", Some("二项"), Some(true), Some("一项"), ["一项"]),
    ("gone", Some("二项"), Some(true), Some("一项"), ["一项"]),
    ("heading", Some("二项"), Some(true), Some("一项"), ["一项"]),
  ])
}

///|
test "大屏, keyboard and mouse: a menu presented beside what was never drawn: beside the window's corner, as the old menu (its panel at 8, 8, as main has it)" {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.menu(menu_items_counting(["复制", "重命名", "删除"], []), from=Of(987654321))
  t.run_for(@ui.move_most_ms)
  let (x, y, _, _) = t.get(Menu).rect
  assert_eq((x, y), (8.0, 8.0))
}

///|
/// An item of a menu called `label` (`off` not to be chosen now, `heading` a heading), its words pushed into `done` as
/// it is chosen.
fn menu_item_doing(label : String, done : Array[String], off? : Bool = false, heading? : Bool = false) -> @sf.MenuItem? {
  Some({ label, icon: "", danger: false, disabled: off, chosen: None, heading, select: fn() { done.push(label) } })
}
