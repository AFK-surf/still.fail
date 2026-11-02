// A panel of the presenters' opened by nothing (@sf.panel `from` Unanchored), a dialog in the middle of the window, on
// 中屏 and 大屏: the old contract, measured on main first (a4c845604), what it does held whatever draws it.

///|
/// Where what a centred panel shows is: its dialog, its title, what it says, its words, its button(s), its close
/// button, the focus.
fn centred_said(t : @ui.Tester) -> String {
  let r = fn(role : @ui.Role, label : String) { t.query(role, label~).map(fn(s) { tenth4(s.rect) }) }
  let w = fn(s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) }) }
  "dialog \{t.query(Dialog).map(fn(s) { (s.label, tenth4(s.rect)) })} title \{w("面板")} says \{w("说明的话")} words \{w("面板里的话，长一些，好看它怎么折行")} ok \{r(Button, "好的")} close \{r(Button, "关闭")} focus \{t.focused().map(fn(s) { "\{s.role} \{s.label}" })}"
}

///|
test "panel centred, 大屏 keyboard and mouse: plain, with what it says, a foot of its own, wide, untitled, a share of the window tall in a tall window and a short one: where it is and what it shows, drawn by the window's tree: as main has it" {
  let out = []
  let drawn = []
  for kind in ["plain", "says", "foot", "wide", "untitled", "tall 800", "tall 500"] {
    let h = if kind == "tall 500" { 500.0 } else { 800.0 }
    let t = menu_tester(1280.0, h, 0)
    let foot = fn(c : @ui.Ctx, close : () -> Unit) {
      if @sf.button(c, "好的", key="ok34", tone=Primary) {
        close()
      }
    }
    match kind {
      "plain" => @sf.panel("面板", panel_test_body([]), from=Unanchored)
      "says" => @sf.panel("面板", panel_test_body([]), from=Unanchored, description="说明的话")
      "foot" => @sf.panel("面板", fits_words_body(@signals.signal("面板里的话，长一些，好看它怎么折行")), from=Unanchored, foot~)
      "wide" => @sf.panel("面板", panel_test_body([]), from=Unanchored, wide=true)
      "untitled" => @sf.panel("", panel_test_body([]), from=Unanchored)
      _ => @sf.panel("面板", panel_column_body(@signals.signal(40), []), from=Unanchored, tall=0.5, foot~)
    }
    t.run_for(@ui.move_most_ms)
    let said = centred_said(t)
    let rows = t.words().filter(fn(x) { x.0 == "第0行" }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) })
    out.push("\{kind}: \{said} row0 \{rows}")
    // (said a dialog titled as it is: an untitled one says no label of its own, read out by what it holds)
    drawn.push(t.query(Dialog).map(fn(_) { tree_said(Dialog, if kind == "untitled" { "" } else { "面板" }) is Some(_) }))
  }
  // (as main has it, a4c845604)
  assert_eq(out, [
    "plain: dialog Some((面板, (380, 315.6, 520, 168.8))) title [(414, 341.6, 44, 30)] says [] words [(424, 390.6, 432, 22)] ok Some((818.2, 432.6, 44, 24)) close Some((851.5, 332.1, 32, 32)) focus None row0 []",
    "says: dialog Some((面板, (380, 302.6, 520, 194.8))) title [(414, 328.6, 44, 30)] says [(414, 365.6, 462, 20)] words [(424, 403.6, 432, 22)] ok Some((818.2, 445.6, 44, 24)) close Some((851.5, 319.1, 32, 32)) focus None row0 []",
    "foot: dialog Some((面板, (380, 314.7, 520, 170.5))) title [(414, 340.7, 44, 30)] says [] words [(424, 389.7, 432, 22)] ok Some((826.5, 435.7, 58, 34)) close Some((851.5, 331.3, 32, 32)) focus None row0 []",
    "wide: dialog Some((面板, (320, 315.6, 640, 168.8))) title [(354, 341.6, 44, 30)] says [] words [(364, 390.6, 552, 22)] ok Some((878.2, 432.6, 44, 24)) close Some((911.5, 332.1, 32, 32)) focus None row0 []",
    "untitled: dialog Some((关闭 面板里的话，长一些，好看它怎么折行 好的, (380, 341.1, 520, 117.8))) title [] says [] words [(424, 365.1, 432, 22)] ok Some((818.2, 407.1, 44, 24)) close Some((851.5, 357.6, 32, 32)) focus None row0 []",
    "tall 800: dialog Some((面板, (380, 173.7, 520, 452.5))) title [(414, 199.7, 44, 30)] says [] words [] ok Some((826.5, 576.7, 58, 34)) close Some((851.5, 190.3, 32, 32)) focus None row0 [(424, 248.7, 432, 22)]",
    "tall 500: dialog Some((面板, (380, 98.7, 520, 302.5))) title [(414, 124.7, 44, 30)] says [] words [] ok Some((826.5, 351.7, 58, 34)) close Some((851.5, 115.3, 32, 32)) focus None row0 [(424, 173.7, 432, 22)]",
  ])
  assert_eq(drawn, [Some(true), Some(true), Some(true), Some(true), Some(true), Some(true), Some(true)])
}

///|
test "panel centred, 大屏 keyboard and mouse: closed by its close button, by Escape, by a press outside it, by its own button: presenting no more, its gone told, the focus back where it was: as main has it" {
  let out = []
  for how in ["close", "escape", "outside", "own", "untitled close pressed"] {
    let t = menu_tester(1280.0, 800.0, 0)
    let gone = Ref(0)
    let said : Array[String] = []
    @sf.panel(if how == "untitled close pressed" { "" } else { "面板" }, panel_test_body(said), from=Unanchored, gone=fn() { gone.val = gone.val + 1 })
    t.run_for(@ui.move_most_ms)
    match how {
      "close" => t.click(Button, label="关闭")
      // (pressed where it is drawn, over the corner of what the panel holds)
      "untitled close pressed" => {
        let (x, y, w, h) = t.get(Button, label="关闭").rect
        t.tap(x + w / 2.0, y + h / 2.0)
      }
      "escape" => t.key(@ui.key_escape)
      "outside" => t.tap(100.0, 700.0)
      _ => t.click(Button, label="好的")
    }
    // (the frame it is closed in, and midway through its way out)
    let at_close = t.focused().map(fn(s) { "\{s.role} \{s.label}" })
    t.run_for(@kit.pop_out_ms / 2.0)
    let midway = t.focused().map(fn(s) { "\{s.role} \{s.label}" })
    t.run_for(@ui.move_most_ms)
    out.push("\{how}: focus closed \{at_close} midway \{midway} then presenting \{@sf.presenting()} gone \{gone.val} said \{said} focus \{t.focused().map(fn(s) { "\{s.role} \{s.label}" })}")
  }
  // (as main has it, a4c845604)
  assert_eq(out, [
    "close: focus closed Some(TextField 按空格输入) midway Some(TextField 按空格输入) then presenting false gone 1 said [] focus Some(TextField 发消息)",
    "escape: focus closed Some(TextField 按空格输入) midway Some(TextField 按空格输入) then presenting false gone 1 said [] focus Some(TextField 发消息)",
    "outside: focus closed Some(TextField 按空格输入) midway Some(TextField 按空格输入) then presenting false gone 1 said [] focus Some(TextField 发消息)",
    "own: focus closed Some(TextField 按空格输入) midway Some(TextField 按空格输入) then presenting false gone 0 said [ok] focus Some(TextField 发消息)",
    // (untitled, its close button pressed where it is drawn: closed. On main, a4c845604, it was not: its close button
    // built under what it holds, the press taken by what scrolls what it holds there, "untitled close pressed: focus
    // closed None midway None then presenting true gone 0 said [] focus None")
    "untitled close pressed: focus closed Some(TextField 按空格输入) midway Some(TextField 按空格输入) then presenting false gone 1 said [] focus Some(TextField 发消息)",
  ])
}

///|
test "panel centred, 大屏 keyboard and mouse: untitled saying something; what it holds there, then nothing, a foot of its own under it; words at its foot on a panel's words' line: as main has it" {
  let out = []
  let w = fn(t : @ui.Tester, s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) }) }
  let dialog = fn(t : @ui.Tester) { t.query(Dialog).map(fn(s) { (s.label, tenth4(s.rect)) }) }
  // (untitled, saying something)
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("", panel_test_body([]), from=Unanchored, description="说明的话")
  t.run_for(@ui.move_most_ms)
  out.push("untitled says: \{centred_said(t)}")
  // (what it holds there, then nothing; its foot of its own words on a panel's words' line)
  let t = menu_tester(1280.0, 800.0, 0)
  let holds = @signals.signal(true)
  @sf.panel(
    "面板",
    fn(c, _) {
      if holds.get() {
        @sf.panel_text(c, fn() { c.text("面板里的话，长一些，好看它怎么折行", style=@sf.paragraph) |> ignore })
      }
    },
    from=Unanchored,
    foot=fn(c, close) {
      c.box(style=@sf.panel_words_in(), fn() { c.text("脚注", style=@sf.paragraph) |> ignore }) |> ignore
      if @sf.button(c, "好的", key="ok34", tone=Primary) {
        close()
      }
    },
  )
  t.run_for(@ui.move_most_ms)
  out.push("holds: dialog \{dialog(t)} words \{w(t, "面板里的话，长一些，好看它怎么折行")} foot words \{w(t, "脚注")} ok \{t.query(Button, label="好的").map(fn(s) { tenth4(s.rect) })}")
  holds.set(false)
  t.run_for(@ui.move_most_ms)
  out.push("holds nothing: dialog \{dialog(t)} foot words \{w(t, "脚注")} ok \{t.query(Button, label="好的").map(fn(s) { tenth4(s.rect) })}")
  // (as main has it, a4c845604)
  assert_eq(out, [
    "untitled says: dialog Some((关闭 说明的话 面板里的话，长一些，好看它怎么折行 好的, (380, 328.1, 520, 143.8))) title [] says [(414, 358.1, 462, 20)] words [(424, 378.1, 432, 22)] ok Some((818.2, 420.1, 44, 24)) close Some((851.5, 344.6, 32, 32)) focus None",
    "holds: dialog Some((面板, (380, 314.7, 520, 170.5))) words [(424, 389.7, 432, 22)] foot words [(780.5, 441.7, 28, 22)] ok Some((826.5, 435.7, 58, 34))",
    "holds nothing: dialog Some((面板, (380, 334.7, 520, 130.5))) foot words [(780.5, 421.7, 28, 22)] ok Some((826.5, 415.7, 58, 34))",
  ])
}

///|
test "panel centred, 大屏 keyboard and mouse: untitled, what it holds reaching under its close button with a ground and a press of its own: the close button drawn under it as main has it, pressed where it is drawn closing the panel, what it holds not (on main, a4c845604, the press taken by what scrolls what it holds)" {
  let t = menu_tester(1280.0, 800.0, 0)
  let under = Ref(0)
  let gone = Ref(0)
  @sf.panel(
    "",
    fn(c, _) {
      let id = c.id("under close")
      if c.clicked(id) {
        under.val = under.val + 1
      }
      c.box(id~, w=Fill(1.0), h=Px(60.0), bg=0x336699FFL, label="底下", fn() {  }) |> ignore
    },
    from=Unanchored,
    gone=fn() { gone.val = gone.val + 1 },
  )
  t.run_for(@ui.move_most_ms)
  let (x, y, w, h) = t.get(Button, label="关闭").rect
  // (in the order drawn: the last of what the close button draws within its box (its mark, whatever ground it has),
  // and the ground of what the panel holds under it)
  let order = t.drawn_order()
  let under_at = order.search_by(fn(d) { d.0 == 0 && d.3 > 300.0 && (d.4 - 60.0).abs() < 0.01 })
  let mut close_at : Int? = None
  for i, d in order {
    if d.1 >= x - 0.01 && d.2 >= y - 0.01 && d.1 + d.3 <= x + w + 0.01 && d.2 + d.4 <= y + h + 0.01 {
      close_at = Some(i)
    }
  }
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  // (both drawn: whether the close button is drawn after what is under it)
  let after = match (under_at, close_at) {
    (Some(u), Some(c)) => Some(c > u)
    _ => None
  }
  // (drawn before it, under it, as on main (646 and 647); the press there closing it, on main closing nothing: Some(false),
  // true, 0, 0)
  assert_eq((after, @sf.presenting(), gone.val, under.val), (Some(false), false, 1, 0))
}

///|
test "panel centred, 大屏 keyboard and mouse: untitled, Tab pressed twice: read out as focused, nothing either time, as main has it" {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("", panel_test_body([]), from=Unanchored)
  t.run_for(@ui.move_most_ms)
  let out = []
  for _ in 0..<2 {
    t.key(@ui.key_tab)
    t.run_for(@ui.move_most_ms)
    out.push(t.focused().map(fn(s) { "\{s.role} \{s.label}" }))
  }
  // (as main has it, a4c845604)
  assert_eq(out, [None, None])
}
