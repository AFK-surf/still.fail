// A panel beside what opened it whose title is as it is now (@sf.panel `live`): its head there or not as its title
// is (none, some, none again), the focus as it opens and where it stays, what was typed kept, beside what opened it
// under it and flipped over it, held short of what it holds by the window. The old contract, measured on main first.

///|
/// Whether a dialog titled `label` (a live one beside what opened it: its presented title, as it was opened) is drawn
/// by the window's tree.
fn live_beside_drawn() -> Bool {
  tree_said(Dialog, "") is Some(_)
}

///|
test "panel live beside what opened it, 大屏 keyboard and mouse: the focus as it opens (focus, not focus, its field given it), its title none, some, none again, typed into between: the focus kept where it was, the field the same and what was typed kept; drawn by the window's tree: as main has it" {
  let out = []
  let drawn = []
  for how in ["focus", "not focus", "field"] {
    let said : Array[String] = []
    let t = menu_tester(1280.0, 800.0, 0)
    let title = @signals.signal("")
    let pf = @ui.Field::new()
    let body = fn(c : @ui.Ctx, close : () -> Unit) {
      if how == "field" {
        c.editor("panel field", field=pf, placeholder="填一下") |> ignore
      }
      panel_test_body(said)(c, close)
    }
    let live = fn() { (title.get(), "", "") }
    match how {
      "not focus" => @sf.panel("", body, from=At(600.0, 300.0, 0.0, 0.0), focus=false, live~)
      "field" => @sf.panel("", body, from=At(600.0, 300.0, 0.0, 0.0), field="panel field", live~)
      _ => @sf.panel("", body, from=At(600.0, 300.0, 0.0, 0.0), live~)
    }
    t.run_for(@ui.move_most_ms)
    let field_id = fn() { t.query(TextField, label="填一下").map(fn(s) { s.id }) }
    let first_field = field_id()
    let at = fn() {
      let d = t.query(Dialog).map(fn(s) { (s.label, tenth4(s.rect)) })
      "\{panel_focus_said(t)} dialog \{@ui.some_text(d.map(fn(d) { "(\{d.0}, \{@ui.rect_text(d.1)})" }))} field same \{field_id() == first_field} text \{pf.text()}"
    }
    let open = at()
    t.type_text("甲")
    live_frames(t, 30)
    title.set("面板")
    live_frames(t, 30)
    let titled = at()
    t.type_text("乙")
    live_frames(t, 30)
    title.set("")
    live_frames(t, 30)
    let again = at()
    drawn.push(live_beside_drawn())
    out.push("\{how}: open {\{open}} titled {\{titled}} again {\{again}}")
  }
  // (as main has it, 2f452a34)
  assert_eq(out, [
    "focus: open {focused None ime (false, , 0, 0) dialog Some((面板里的话，长一些，好看它怎么折行 好的, (600, 306, 296, 68))) field same true text } titled {focused None ime (false, , 0, 0) dialog Some((面板 面板里的话，长一些，好看它怎么折行 好的, (600, 306, 296, 98))) field same true text } again {focused None ime (false, , 0, 0) dialog Some((面板里的话，长一些，好看它怎么折行 好的, (600, 306, 296, 68))) field same true text }",
    "not focus: open {focused Some(TextField 发消息) ime (true, , 0, 0) dialog Some((面板里的话，长一些，好看它怎么折行 好的, (600, 306, 296, 68))) field same true text } titled {focused Some(TextField 发消息) ime (true, 甲, 1, 1) dialog Some((面板 面板里的话，长一些，好看它怎么折行 好的, (600, 306, 296, 98))) field same true text } again {focused Some(TextField 发消息) ime (true, 甲乙, 2, 2) dialog Some((面板里的话，长一些，好看它怎么折行 好的, (600, 306, 296, 68))) field same true text }",
    "field: open {focused Some(TextField 填一下) ime (true, , 0, 0) dialog Some((填一下 面板里的话，长一些，好看它怎么折行 好的, (600, 306, 296, 107))) field same true text } titled {focused Some(TextField 填一下) ime (true, 甲, 1, 1) dialog Some((面板 填一下 面板里的话，长一些，好看它怎么折行 好的, (600, 306, 296, 137))) field same true text 甲} again {focused Some(TextField 填一下) ime (true, 甲乙, 2, 2) dialog Some((填一下 面板里的话，长一些，好看它怎么折行 好的, (600, 306, 296, 107))) field same true text 甲乙}",
  ])
  assert_eq(drawn, [true, true, true])
}

///|
test "panel live beside what opened it, 大屏 keyboard and mouse: opened under what opened it, opened flipped over it for want of room below (two panels, each where it was put), its title none, some, none again (frames as the display draws them): where it is, its title and words, whether it stands above: as main has it" {
  let out = []
  for y in [100.0, 780.0] {
    let t = menu_tester(1280.0, 800.0, 0)
    let title = @signals.signal("")
    let up : Array[Bool] = []
    @sf.panel(
      "",
      fn(c, close) {
        up.push(@sf.panel_opens_up())
        panel_test_body([])(c, close)
      },
      from=At(600.0, y, 0.0, 0.0),
      live=fn() { (title.get(), "", "") },
    )
    t.run_for(@ui.move_most_ms)
    let w = fn(s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) }) }
    for s in ["", "面板", ""] {
      title.set(s)
      live_frames(t, 30)
      let d = t.query(Dialog).map(fn(s) { (s.label, tenth4(s.rect)) })
      let line = "\{y} \{s}: dialog \{@ui.some_text(d.map(fn(d) { "(\{d.0}, \{@ui.rect_text(d.1)})" }))} title \{@ui.list_text(w("面板").map(@ui.rect_text))} words \{@ui.list_text(w("面板里的话，长一些，好看它怎么折行").map(@ui.rect_text))} button \{@ui.some_text(t.query(Button, label="好的").map(fn(s) { tenth4(s.rect) }).map(@ui.rect_text))} up \{@ui.some_text(up.last())}"
      out.push(line)
    }
  }
  // (as main has it, 2f452a34)
  assert_eq(out, [
    "100 : dialog Some((面板里的话，长一些，好看它怎么折行 好的, (600, 106, 296, 68))) title [] words [(616, 112, 264, 22)] button Some((840, 138, 44, 24)) up Some(false)",
    "100 面板: dialog Some((面板 面板里的话，长一些，好看它怎么折行 好的, (600, 106, 296, 98))) title [(616, 118, 264, 20)] words [(616, 142, 264, 22)] button Some((840, 168, 44, 24)) up Some(false)",
    "100 : dialog Some((面板里的话，长一些，好看它怎么折行 好的, (600, 106, 296, 68))) title [] words [(616, 112, 264, 22)] button Some((840, 138, 44, 24)) up Some(false)",
    "780 : dialog Some((面板里的话，长一些，好看它怎么折行 好的, (600, 706, 296, 68))) title [] words [(616, 712, 264, 22)] button Some((840, 738, 44, 24)) up Some(true)",
    "780 面板: dialog Some((面板 面板里的话，长一些，好看它怎么折行 好的, (600, 676, 296, 98))) title [(616, 688, 264, 20)] words [(616, 712, 264, 22)] button Some((840, 738, 44, 24)) up Some(true)",
    "780 : dialog Some((面板里的话，长一些，好看它怎么折行 好的, (600, 706, 296, 68))) title [] words [(616, 712, 264, 22)] button Some((840, 738, 44, 24)) up Some(true)",
  ])
}

///|
test "panel live beside what opened it, 大屏 keyboard and mouse: held short of what it holds by the window, scrolled, its title none, some, none again (frames as the display draws them): where its rows and button are, what the wheel scrolls after, told held: as main has it" {
  let held : Array[Bool] = []
  let said : Array[String] = []
  let t = menu_tester(1280.0, 500.0, 0)
  let title = @signals.signal("")
  @sf.panel(
    "",
    fn(c, close) {
      held.push(@sf.panel_held())
      for i in 0..<40 {
        @sf.panel_text(c, fn() { c.text("第\{i}行", style=@sf.paragraph) |> ignore })
      }
      @sf.panel_foot(c, fn() {
        @sf.panel_button(c, "ok", "好的", tone=Filled, on_press=fn() {
          said.push("ok")
          close()
        }) |> ignore
      })
    },
    from=At(600.0, 100.0, 0.0, 0.0),
    live=fn() { (title.get(), "", "") },
  )
  t.run_for(@ui.move_most_ms)
  let w = fn(s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) }) }
  let at = fn() {
    "dialog \{@ui.some_text(t.query(Dialog).map(fn(s) { tenth4(s.rect) }).map(@ui.rect_text))} title \{@ui.list_text(w("面板").map(@ui.rect_text))} row0 \{@ui.list_text(w("第0行").map(@ui.rect_text))} row10 \{@ui.list_text(w("第10行").map(@ui.rect_text))} button \{@ui.some_text(t.query(Button, label="好的").map(fn(s) { tenth4(s.rect) }).map(@ui.rect_text))} held \{@ui.some_text(held.last())}"
  }
  let (dx, dy, dw, dh) = t.get(Dialog).rect
  t.wheel(dx + dw / 2.0, dy + dh / 2.0, 120.0)
  t.run_for(@ui.move_most_ms)
  let out = ["scrolled \{at()}"]
  for s in ["面板", ""] {
    title.set(s)
    live_frames(t, 30)
    out.push("\{s}: \{at()}")
    let (dx, dy, dw, dh) = t.get(Dialog).rect
    t.wheel(dx + dw / 2.0, dy + dh / 2.0, 120.0)
    t.run_for(@ui.move_most_ms)
    out.push("\{s} wheel: \{at()}")
  }
  // (as main has it, 2f452a34)
  assert_eq(out, [
    "scrolled dialog Some((600, 8, 296, 484)) title [] row0 [(616, -106, 264, 22)] row10 [(616, 114, 264, 22)] button Some((840, 778, 44, 24)) held Some(true)",
    "面板: dialog Some((600, 8, 296, 484)) title [(616, 20, 264, 20)] row0 [(616, -76, 264, 22)] row10 [(616, 144, 264, 22)] button Some((840, 808, 44, 24)) held Some(true)",
    "面板 wheel: dialog Some((600, 8, 296, 484)) title [(616, 20, 264, 20)] row0 [(616, -196, 264, 22)] row10 [(616, 24, 264, 22)] button Some((840, 688, 44, 24)) held Some(true)",
    ": dialog Some((600, 8, 296, 484)) title [] row0 [(616, -226, 264, 22)] row10 [(616, -6, 264, 22)] button Some((840, 658, 44, 24)) held Some(true)",
    " wheel: dialog Some((600, 8, 296, 484)) title [] row0 [(616, -346, 264, 22)] row10 [(616, -126, 264, 22)] button Some((840, 538, 44, 24)) held Some(true)",
  ])
  // (scrolled to its end with its title shown again: its last row seen whole (its glyphs drawn within the edges they
  // are cut to), its button in the window; pressed at its middle, said and closed)
  title.set("面板")
  live_frames(t, 30)
  let (dx, dy, dw, dh) = t.get(Dialog).rect
  for _ in 0..<10 {
    t.wheel(dx + dw / 2.0, dy + dh / 2.0, 400.0)
    t.run_for(@ui.move_most_ms)
  }
  let button = t.query(Button, label="好的").map(fn(s) { tenth4(s.rect) })
  let seen = rows_seen(t)
  let bottom = "seen (\{@ui.some_text(seen.0)}, \{@ui.some_text(seen.1)}) title \{@ui.list_text(w("面板").map(@ui.rect_text))} button \{@ui.some_text(button.map(@ui.rect_text))} in window \{@ui.some_text(button.map(fn(b) { b.1 >= 0.0 && b.1 + b.3 <= 500.0 }))}"
  // (a press at its middle, where the hit test finds it: not said to it)
  let (bx, by, bw, bh) = t.get(Button, label="好的").rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.run_for(@ui.move_most_ms)
  // (as main has it, 2f452a34)
  assert_eq([bottom, "said \{@ui.list_text(said)} presenting \{@sf.presenting()}"], [
    "seen (Some(第20行), Some(第39行)) title [(616, 20, 264, 20)] button Some((840, 456, 44, 24)) in window Some(true)",
    "said [ok] presenting false",
  ])
}
