// A pick of the presenters' (@sf.pick) on 中屏 and 大屏, beside what opened it: short (or with no search) a menu of
// its choices, the one chosen checked, what each is under its words and its value at its row's end; long, a panel with
// a search over its list, the words typed finding by label, note and value, Enter picking the first found, none found
// said so, the list scrolling past its most. On 小屏 a sheet still. What each does, as the old presenter has it
// (pick_popover), held whatever draws it.

///|
/// Choices 第1项 … 第n项 (c1 … cn), the first noted 最近用过, the third valued 3 个.
fn pick_choices(n : Int) -> Array[@sf.Choice] {
  Array::makei(n, fn(i) {
    @sf.choice("c\{i + 1}", "第\{i + 1}项", note=if i == 0 { "最近用过" } else { "" }, value=if i == 2 { "3 个" } else { "" })
  })
}

///|
/// 大屏, keyboard and mouse, chat A open; a pick of `n` (c2 chosen) presented at a point, come in; what was chosen.
fn pick_at_point(n : Int, chosen : Ref[String], search? : Bool = true) -> @ui.Tester {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.pick("选一个", pick_choices(n), "c2", fn(k) { chosen.val = k }, from=@sf.at_point(600.0, 300.0), search~)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// What is said of the pick now: the roles and labels of its rows, checked or not, and what has the focus.
fn pick_said(t : @ui.Tester) -> String {
  let rows = t.all(MenuItemRadio).map(fn(s) { "\{s.label}=\{s.check}" }) + t.all(MenuItem).map(fn(s) { s.label }) +
    t.all(Button).filter(fn(s) { s.label.has_prefix("第") }).map(fn(s) { "button \{s.label}" })
  let f = t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none")
  "rows \{rows} focus \{f} menus \{t.all(Menu).map(fn(s) { s.rect })}"
}

///|
test "pick, short, 大屏 keyboard and mouse: its title, its choices, c2 checked, the note under 第1项 and 3 个 at 第3项's end; 第3项 clicked: c3 chosen, gone at once" {
  let chosen = Ref("")
  let t = pick_at_point(3, chosen)
  println("PICKSAID short \{pick_said(t)}")
  // (a menu, its panel with the focus, its choices radios, c2 on)
  let rows = t.all(MenuItemRadio).map(fn(s) { (s.label, s.check) })
  let panel = t.focused().map(fn(s) { s.role is Menu })
  let seen = (t.find("选一个") is Some(_), t.find("最近用过") is Some(_), t.find("3 个") is Some(_))
  t.tap_text("第3项")
  t.frame()
  assert_eq(
    (rows, panel, seen, chosen.val, @sf.presenting(), t.find("第1项") is None),
    ([("第1项", Some(Off)), ("第2项", Some(On)), ("第3项", Some(Off))], Some(true), (true, true, true), "c3", false, true),
  )
}

///|
test "pick, short, 大屏 keyboard and mouse: Down to the first, Down again, Enter: c2 chosen; another, Escape: none chosen, closed" {
  let chosen = Ref("")
  let t = pick_at_point(3, chosen)
  t.key(@ui.key_code_down)
  t.key(@ui.key_code_down)
  println("PICKSAID keys \{pick_said(t)}")
  t.key(@ui.key_code_enter)
  t.frame()
  let first = (chosen.val, @sf.presenting())
  let chosen2 = Ref("")
  let t2 = pick_at_point(3, chosen2)
  t2.key(@ui.key_escape)
  t2.frame()
  assert_eq((first, chosen2.val, @sf.presenting()), (("c2", false), "", false))
}

///|
test "pick, long, 大屏 keyboard and mouse: its search has the focus; 第11 typed: 第11项 alone; x more: none found said; back to 第11, Enter: c11 chosen, closed" {
  let chosen = Ref("")
  let t = pick_at_point(@sf.pick_search_from + 4, chosen)
  println("PICKSAID long \{pick_said(t)} field \{t.field_words()}")
  // (a dialog titled so, its search with the focus, each choice a button called by its words and its note)
  let shape = (
    t.query(Dialog, label="选一个") is Some(_),
    t.focused().map(fn(s) { (s.role is TextField, s.label) }),
    t.all(Button).filter(fn(s) { s.label.has_prefix("第") }).length(),
    t.query(Button, label="第1项 最近用过") is Some(_),
  )
  let all = (t.find("第2项") is Some(_), t.find("第11项") is Some(_))
  t.type_text("第11")
  let found = (t.find("第2项") is None, t.find("第11项") is Some(_), t.field_words())
  t.type_text("x")
  let none = t.find("没有匹配的结果") is Some(_)
  t.backspace()
  t.key(@ui.key_code_enter)
  t.frame()
  assert_eq(
    (shape, all, found, none, chosen.val, @sf.presenting()),
    ((true, Some((true, "搜索")), 12, true), (true, true), (true, true, "第11"), true, "c11", false),
  )
}

///|
test "pick, long, 大屏 keyboard and mouse: a choice clicked: chosen, closed; another, Escape: closed, none chosen" {
  let chosen = Ref("")
  let t = pick_at_point(@sf.pick_search_from + 4, chosen)
  t.tap_text("第5项")
  t.frame()
  let clicked = (chosen.val, @sf.presenting())
  let chosen2 = Ref("")
  let t2 = pick_at_point(@sf.pick_search_from + 4, chosen2)
  t2.key(@ui.key_escape)
  t2.frame()
  assert_eq((clicked, chosen2.val, @sf.presenting()), (("c5", false), "", false))
}

///|
test "pick, long, 大屏 keyboard and mouse: 30 choices, its list no taller than its most; the wheel over it scrolls it, the search staying" {
  let chosen = Ref("")
  let t = pick_at_point(30, chosen)
  let (_, py, _, ph) = t.get(Dialog, label="选一个").rect
  let (_, y1, _, _) = t.get(Button, label="第1项 最近用过").rect
  let field = t.find("搜索")
  let (wx, wy) = (680.0, y1 + 120.0)
  t.wheel(wx, wy, 200.0)
  t.run_for(@ui.move_most_ms)
  let (_, y1b, _, _) = t.get(Button, label="第1项 最近用过").rect
  println("PICKSAID scroll panel \{py} \{ph} row1 \{y1} -> \{y1b} field \{field} -> \{t.find("搜索")}")
  assert_eq((ph <= @sf.pick_list_most + 80.0, y1b < y1, t.find("搜索") == field), (true, true, true))
}

///|
test "pick, short, with no search though long: a menu of its choices, no search; Down, Enter: c1" {
  let chosen = Ref("")
  let t = pick_at_point(@sf.pick_search_from + 4, chosen, search=false)
  let no_field = t.find("搜索") is None
  t.key(@ui.key_code_down)
  t.key(@ui.key_code_enter)
  t.frame()
  assert_eq((no_field, chosen.val, @sf.presenting()), (true, "c1", false))
}

///|
test "pick, 小屏 touch: a sheet of its choices still; 第3项 tapped: c3" {
  new_run()
  let src = fixture("chat")
  wide_src.val = Some(src)
  open_chat(chat_a)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let chosen = Ref("")
  @sf.pick("选一个", pick_choices(3), "c2", fn(k) { chosen.val = k }, from=@sf.at_point(200.0, 300.0))
  t.run_for(@ui.move_most_ms)
  let menus = t.all(Menu).length()
  t.tap_text("第3项")
  t.run_for(@ui.move_most_ms)
  assert_eq((menus, chosen.val, @sf.presenting()), (0, "c3", false))
}

///|
test "pick, short, 大屏 keyboard and mouse: drawn by the window's tree, a menu titled so; its note under 第1项 and 3 个 at 第3项's end words of its own" {
  let chosen = Ref("")
  let _t = pick_at_point(3, chosen)
  let tree = @ui.view_tree().unwrap()
  let words = tree.drawn().filter(fn(d) { d.words == "最近用过" || d.words == "3 个" }).map(fn(d) { d.words })
  assert_eq((tree_said(Menu, "选一个") is Some(_), words), (true, ["最近用过", "3 个"]))
}

///|
test "pick, short, 大屏 keyboard and mouse: what 第1项 is (最近用过) under its words, as far in as they are, past the check's column" {
  let chosen = Ref("")
  let _t = pick_at_point(3, chosen)
  let tree = @ui.view_tree().unwrap()
  let x_of = fn(w : String) { tree.drawn().filter(fn(d) { d.words == w }).map(fn(d) { d.x }) }
  let (note, words) = (x_of("最近用过"), x_of("第1项"))
  // (each made, once)
  assert_eq((note.length(), words.length()), (1, 1))
  assert_eq(note, words)
}

///|
test "pick, long, 大屏 keyboard and mouse: drawn by the window's tree, a panel titled so; its choices words of its own" {
  let chosen = Ref("")
  let _t = pick_at_point(@sf.pick_search_from + 4, chosen)
  let tree = @ui.view_tree().unwrap()
  let rows = tree.drawn().filter(fn(d) { d.words == "第1项" || d.words == "最近用过" }).map(fn(d) { d.words })
  assert_eq((tree_said(Dialog, "选一个") is Some(_), rows), (true, ["第1项", "最近用过"]))
}

///|
test "pick, long, 大屏 keyboard and mouse: the message field focused, opened: its search's; Escape: closed, the message field's again" {
  let t = menu_tester(1280.0, 800.0, 0)
  let said = fn() { t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none") }
  let before = said()
  let chosen = Ref("")
  @sf.pick("选一个", pick_choices(@sf.pick_search_from + 4), "c2", fn(k) { chosen.val = k }, from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  let open = said()
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_eq((before, open, said(), chosen.val), ("TextField 发消息", "TextField 搜索", "TextField 发消息", ""))
}

///|
test "pick, long, 大屏 keyboard and mouse: at a point, its panel 6 under it; 9 choices fitting, 12 scrolling: as tall as main has it (349.6, 364.8)" {
  let out = []
  for n in [9, 12] {
    let t = menu_tester(1280.0, 800.0, 0)
    @sf.pick("选一个", Array::makei(n, fn(i) { @sf.choice("c\{i}", "第\{i + 1}项") }), "c1", fn(_) {  }, from=@sf.at_point(600.0, 300.0))
    t.run_for(@ui.move_most_ms)
    let (x, y, w, h) = t.get(Dialog, label="选一个").rect
    out.push((x, y, w, (h * 10.0).round() / 10.0))
  }
  assert_eq(out, [(600.0, 306.0, 220.0, 349.6), (600.0, 306.0, 220.0, 364.8)])
}

///|
test "pick, long, 大屏 keyboard and mouse: 9 found in a window just tall enough for them (464 high: its panel, 106 down, 349.6 tall, 8 off its foot), the same opened there or in one too short for them (300) and grown to it: its panel and its last choice where they are" {
  let at = fn(short : Bool) raise {
    let t = menu_tester(1280.0, if short { 300.0 } else { 464.0 }, 0)
    let choices = Array::makei(9, fn(i) { @sf.choice("j\{i}", "甲\{i + 1}") }) +
      Array::makei(3, fn(i) { @sf.choice("y\{i}", "乙\{i + 1}") })
    @sf.pick("选一个", choices, "j0", fn(_) {  }, from=@sf.at_point(600.0, 100.0))
    t.run_for(@ui.move_most_ms)
    t.type_text("甲")
    t.run_for(@ui.move_most_ms)
    if short {
      t.resize(1280.0, 464.0)
      t.run_for(@ui.move_most_ms)
    }
    (t.get(Dialog, label="选一个").rect, t.get(Button, label="甲9").rect)
  }
  let (whole, grown) = (at(false), at(true))
  assert_eq(grown, whole)
}

///|
test "pick, long, 大屏 keyboard and mouse: its last row's reach past its list, into the panel's foot, pressed: as main has it, with 9 single-line choices fitting, 12 scrolling" {
  let open = fn(n : Int, chosen : Ref[String]) {
    let t = menu_tester(1280.0, 800.0, 0)
    @sf.pick("选一个", Array::makei(n, fn(i) { @sf.choice("c\{i + 1}", "第\{i + 1}项") }), "c1", fn(k) { chosen.val = k }, from=@sf.at_point(600.0, 300.0))
    t.run_for(@ui.move_most_ms)
    t
  }
  // (9 fitting: the whole of its last row drawn, reaching past the list's foot (the panel's less its padding) by a
  // row's reach)
  let chosen = Ref("")
  let t = open(9, chosen)
  let (dx, dy, dw, dh) = t.get(Dialog, label="选一个").rect
  let (_, ry, _, rh) = t.get(Button, label="第9项").rect
  let list_foot = dy + dh - @sf.panel_pad
  let reach = ry + rh - list_foot
  let fits = (dh, reach > 0.5 && reach < 2.0)
  t.tap(dx + dw / 2.0, list_foot + reach / 2.0)
  t.run_for(@ui.move_most_ms)
  let fit_pressed = (chosen.val, @sf.presenting())
  // (12 scrolling, at its top: the same band under its list's foot)
  let chosen2 = Ref("")
  let t2 = open(12, chosen2)
  let (dx2, dy2, dw2, dh2) = t2.get(Dialog, label="选一个").rect
  let foot2 = dy2 + dh2 - @sf.panel_pad
  t2.tap(dx2 + dw2 / 2.0, foot2 + reach / 2.0)
  t2.run_for(@ui.move_most_ms)
  assert_eq((fits.1, fit_pressed, (chosen2.val, @sf.presenting())), (true, ("c9", false), ("", true)))
}

///|
test "pick, long, 大屏 keyboard and mouse: a choice's words 20 a line, where main has them (第2项 79.8 under the panel's top, 16 in)" {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.pick("选一个", Array::makei(12, fn(i) { @sf.choice("c\{i}", "第\{i + 1}项") }), "c0", fn(_) {  }, from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  let (dx, dy, _, _) = t.get(Dialog, label="选一个").rect
  let tree = @ui.view_tree().unwrap()
  let at = tree.drawn().filter(fn(d) { d.words == "第2项" }).map(fn(d) { (d.x - dx, ((d.y - dy) * 10.0).round() / 10.0, d.h) })
  assert_eq(at, [(16.0, 79.8, 20.0)])
}

///|
test "pick, long, 大屏 keyboard and mouse: a choice's value at its row's end, where main has it (3 条新消息, 144 in, 115.4 under the panel's top, 16.8 high)" {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.pick("选一个", Array::makei(12, fn(i) { @sf.choice("c\{i}", "第\{i + 1}项", value=if i == 2 { "3 条新消息" } else { "" }) }), "c0", fn(_) {  }, from=@sf.at_point(600.0, 300.0))
  t.run_for(@ui.move_most_ms)
  let (dx, dy, _, _) = t.get(Dialog, label="选一个").rect
  let tree = @ui.view_tree().unwrap()
  let at = tree.drawn().filter(fn(d) { d.words == "3 条新消息" }).map(fn(d) { (d.x - dx, ((d.y - dy) * 10.0).round() / 10.0, (d.h * 10.0).round() / 10.0) })
  assert_eq(at, [(144.0, 115.4, 16.8)])
}
