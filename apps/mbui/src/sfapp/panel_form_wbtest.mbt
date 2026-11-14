// A panel of the presenters' that is a form (@sf.panel `form`): what is filled in and said, a dialog in the middle of
// the window whatever opened it, a share of the window tall or not; its field given the focus as it opens: the old
// contract, measured on main first, what it does held whatever draws it.

///|
/// A form's body: a field (given the focus as it opens, by `field`), `lines` lines of words, its button.
fn form_body(said : Array[String], pf : @ui.Field, lines : @signals.Signal[Int]) -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, close) {
    c.editor("form field", field=pf, placeholder="填一下") |> ignore
    for i in 0..<lines.get() {
      @sf.panel_text(c, fn() { c.text("第\{i}行", style=@sf.paragraph) |> ignore })
    }
    panel_test_body(said)(c, close)
  }
}

///|
test "panel a form, 大屏 keyboard and mouse and a tablet by touch: at a point, a share of the window tall, opened by nothing, in a short window, its rows more then fewer, no field named: in the middle, its field (the first) given the focus, typed into, its last row seen and its button pressed in a short window, closed by Escape, the focus back; drawn by the window's tree: as main has it" {
  let out = []
  let drawn = []
  for kind in ["at", "tall at", "middle", "short", "tablet", "grown", "unfield"] {
    let said : Array[String] = []
    let (w, h, platform) = match kind {
      "short" => (1280.0, 500.0, 0)
      "tablet" => (840.0, 900.0, 2)
      _ => (1280.0, 800.0, 0)
    }
    let t = menu_tester(w, h, platform)
    let pf = @ui.Field::new()
    let lines = @signals.signal(if kind == "short" { 30 } else { 0 })
    let at : @sf.Anchor = if kind == "middle" { Unanchored } else { At(600.0, 100.0, 0.0, 0.0) }
    match kind {
      "tall at" => @sf.panel("面板", form_body(said, pf, lines), from=at, form=true, tall=0.72, field="form field")
      "middle" => @sf.panel("面板", form_body(said, pf, lines), from=at, form=true, description="说明的话", field="form field")
      // (no field named: the first that takes the focus given it, as the old frame's trapping overlay does)
      "unfield" => @sf.panel("面板", form_body(said, pf, lines), from=at, form=true)
      _ => @sf.panel("面板", form_body(said, pf, lines), from=at, form=true, field="form field")
    }
    t.run_for(@ui.move_most_ms)
    let r = fn(role : @ui.Role, label : String) { t.query(role, label~).map(fn(s) { tenth4(s.rect) }) }
    let open = "dialog \{@ui.some_text(r(Dialog, "面板").map(@ui.rect_text))} field \{@ui.some_text(r(TextField, "填一下").map(@ui.rect_text))} ok \{@ui.some_text(r(Button, "好的").map(@ui.rect_text))} focus \{panel_focus_said(t)}"
    drawn.push(tree_said(Dialog, "面板") is Some(_))
    t.type_text("甲")
    t.run_for(@ui.move_most_ms)
    let typed = "field \{pf.text()}"
    // (what it holds more, then less: as tall as it holds each time)
    let grown = if kind == "grown" {
      lines.set(8)
      t.run_for(@ui.move_most_ms)
      let more = "more: dialog \{@ui.some_text(r(Dialog, "面板").map(@ui.rect_text))} ok \{@ui.some_text(r(Button, "好的").map(@ui.rect_text))}"
      lines.set(2)
      t.run_for(@ui.move_most_ms)
      " | \{more} less: dialog \{@ui.some_text(r(Dialog, "面板").map(@ui.rect_text))} ok \{@ui.some_text(r(Button, "好的").map(@ui.rect_text))}"
    } else {
      ""
    }
    // (in a short window, what it holds scrolled as far as it goes: its button where it is then)
    let far = if kind == "short" {
      match t.query(Dialog, label="面板") {
        Some(d) => {
          t.wheel(d.rect.0 + d.rect.2 / 2.0, d.rect.1 + d.rect.3 / 2.0, 3000.0)
          t.run_for(@ui.move_most_ms)
          // (its last line seen: each of its glyphs drawn (alpha) within the straight edges it is cut to, its clip and its
          // outer one where it has one, as panel_reach_said reads them; none drawn: not seen)
          let drawn = t.drawn_instances()
          let seen = t.words().filter(fn(x) { x.0 == "第29行" }).map(fn(x) {
            let glyphs = drawn.filter(fn(g) {
              g[5] == 1.0 && g[11] > 0.0 && g[0] >= x.1 - 0.01 && g[0] < x.1 + x.3 && g[1] >= x.2 - 0.01 && g[1] < x.2 + x.4
            })
            glyphs.length() > 0 &&
            glyphs.iter().all(fn(g) {
              let outer = g[44] > 0.0 || g[45] > 0.0 || g[46] > 0.0 || g[47] > 0.0
              let (y0, y1) = (dmax(g[17], if outer { g[41] } else { g[1] }), dmin(g[19], if outer { g[43] } else { g[1] + g[3] }))
              let (x0, x1) = (dmax(g[16], if outer { g[40] } else { g[0] }), dmin(g[18], if outer { g[42] } else { g[0] + g[2] }))
              g[1] >= y0 - 0.01 && g[1] + g[3] <= y1 + 0.01 && g[0] >= x0 - 0.01 && g[0] + g[2] <= x1 + 0.01
            })
          })
          let ok = r(Button, "好的")
          let last = t.words().filter(fn(x) { x.0 == "第29行" }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) })
          // (its button pressed at its middle as it is drawn: said, the panel closed)
          match t.query(Button, label="好的") {
            Some(b) => {
              t.tap(b.rect.0 + b.rect.2 / 2.0, b.rect.1 + b.rect.3 / 2.0)
              t.run_for(@ui.move_most_ms)
            }
            None => ()
          }
          " | far: ok \{@ui.some_text(ok.map(@ui.rect_text))} last \{@ui.list_text(last.map(@ui.rect_text))} seen \{@ui.list_text(seen)} | ok pressed: said \{@ui.list_text(said)} presenting \{@sf.presenting()} focus \{panel_focus_said(t)}"
        }
        None => " | far: none"
      }
    } else {
      ""
    }
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    out.push("\{kind}: \{open} | \{typed}\{grown}\{far} | escape: presenting \{@sf.presenting()} focus \{panel_focus_said(t)}")
  }
  // (as main has it: drawn by the old frame, the same test, before this)
  assert_eq((out, drawn), (
    [
      "at: dialog Some((380, 287, 520, 226)) field Some((404, 362, 472, 39)) ok Some((826, 459, 44, 24)) focus focused Some(TextField 填一下) ime (true, , 0, 0) | field 甲 | escape: presenting false focus focused Some(TextField 发消息) ime (true, , 0, 0)",
      "tall at: dialog Some((380, 287, 520, 226)) field Some((404, 362, 472, 39)) ok Some((826, 459, 44, 24)) focus focused Some(TextField 填一下) ime (true, , 0, 0) | field 甲 | escape: presenting false focus focused Some(TextField 发消息) ime (true, , 0, 0)",
      "middle: dialog Some((380, 274, 520, 252)) field Some((404, 375, 472, 39)) ok Some((826, 472, 44, 24)) focus focused Some(TextField 填一下) ime (true, , 0, 0) | field 甲 | escape: presenting false focus focused Some(TextField 发消息) ime (true, , 0, 0)",
      "short: dialog Some((380, 24, 520, 452)) field Some((404, 99, 472, 39)) ok Some((826, 1336, 44, 24)) focus focused Some(TextField 填一下) ime (true, , 0, 0) | field 甲 | far: ok Some((826, 422, 44, 24)) last [(414, 342, 452, 22)] seen [true] | ok pressed: said [ok] presenting false focus focused None ime (false, , 0, 0) | escape: presenting false focus focused None ime (false, , 0, 0)",
      "tablet: dialog Some((160, 337, 520, 226)) field Some((184, 412, 472, 39)) ok Some((604, 509, 46, 24)) focus focused Some(TextField 填一下) ime (true, , 0, 0) | field 甲 | escape: presenting false focus focused None ime (false, , 0, 0)",
      "grown: dialog Some((380, 287, 520, 226)) field Some((404, 362, 472, 39)) ok Some((826, 459, 44, 24)) focus focused Some(TextField 填一下) ime (true, , 0, 0) | field 甲 | more: dialog Some((380, 135, 520, 530)) ok Some((826, 611, 44, 24)) less: dialog Some((380, 249, 520, 302)) ok Some((826, 497, 44, 24)) | escape: presenting false focus focused Some(TextField 发消息) ime (true, , 0, 0)",
      "unfield: dialog Some((380, 287, 520, 226)) field Some((404, 362, 472, 39)) ok Some((826, 459, 44, 24)) focus focused Some(TextField 填一下) ime (true, , 0, 0) | field 甲 | escape: presenting false focus focused Some(TextField 发消息) ime (true, , 0, 0)",
    ],
    [true, true, true, true, true, true, true],
  ))
}

///|
test "panel a form at a point, its field given the focus and holding it, 大屏 keyboard and mouse: closed by its close button, by Escape, by a press outside, by its own button: where the focus is then, at once and after: as main has it" {
  let out = []
  for how in ["close", "escape", "outside", "own"] {
    let said : Array[String] = []
    let t = menu_tester(1280.0, 800.0, 0)
    let pf = @ui.Field::new()
    @sf.panel("面板", form_body(said, pf, @signals.signal(0)), from=At(600.0, 100.0, 0.0, 0.0), form=true, field="form field")
    t.run_for(@ui.move_most_ms)
    let open = panel_focus_said(t)
    match how {
      "close" => t.click(Button, label="关闭")
      "escape" => t.key(@ui.key_escape)
      "outside" => t.tap(100.0, 700.0)
      _ => t.click(Button, label="好的")
    }
    let at_close = panel_focus_said(t)
    t.run_for(@ui.move_most_ms)
    out.push("\{how}: open {\{open}} closed {\{at_close}} after {\{panel_focus_said(t)}} said \{@ui.list_text(said)} presenting \{@sf.presenting()}")
  }
  // (as main has it: its close button and its own let its field go, the focus nowhere after; Escape and a press
  // outside give it back first, to what had it as it opened)
  assert_eq(out, [
    "close: open {focused Some(TextField 填一下) ime (true, , 0, 0)} closed {focused None ime (false, , 0, 0)} after {focused None ime (false, , 0, 0)} said [] presenting false",
    "escape: open {focused Some(TextField 填一下) ime (true, , 0, 0)} closed {focused Some(TextField 发消息) ime (true, , 0, 0)} after {focused Some(TextField 发消息) ime (true, , 0, 0)} said [] presenting false",
    "outside: open {focused Some(TextField 填一下) ime (true, , 0, 0)} closed {focused Some(TextField 发消息) ime (true, , 0, 0)} after {focused Some(TextField 发消息) ime (true, , 0, 0)} said [] presenting false",
    "own: open {focused Some(TextField 填一下) ime (true, , 0, 0)} closed {focused None ime (false, , 0, 0)} after {focused None ime (false, , 0, 0)} said [ok] presenting false",
  ])
}

///|
test "panel a form at a point, its field holding the focus, its own button closing it and opening another form with a field of its own: that field has the focus as it closes and after, typed into; the first's let go of before, not after" {
  let said : Array[String] = []
  let t = menu_tester(1280.0, 800.0, 0)
  let pf = @ui.Field::new()
  let other = @ui.Field::new()
  let next = fn(c : @ui.Ctx, close : () -> Unit) {
    c.editor("next field", field=other, placeholder="另一框") |> ignore
    panel_test_body([])(c, close)
  }
  @sf.panel("面板", from=At(600.0, 100.0, 0.0, 0.0), form=true, field="form field", fn(c, close) {
    c.editor("form field", field=pf, placeholder="填一下") |> ignore
    @sf.panel_foot(c, fn() {
      @sf.panel_button(c, "ok", "好的", tone=Filled, on_press=fn() {
        said.push("ok")
        close()
        @sf.panel("另一个", next, from=At(600.0, 100.0, 0.0, 0.0), form=true, field="next field")
      }) |> ignore
    })
  })
  t.run_for(@ui.move_most_ms)
  let open = panel_focus_said(t)
  t.click(Button, label="好的")
  let at_close = panel_focus_said(t)
  t.run_for(@ui.move_most_ms)
  let after = panel_focus_said(t)
  t.type_text("乙")
  t.run_for(@ui.move_most_ms)
  // (as main has it: the other form's field the focus's from the frame the first closes in, typed into; the first's
  // field none of it)
  assert_eq([open, at_close, after, "填 \{pf.text()} 另 \{other.text()} said \{@ui.list_text(said)}"], [
    "focused Some(TextField 填一下) ime (true, , 0, 0)",
    "focused Some(TextField 另一框) ime (true, , 0, 0)",
    "focused Some(TextField 另一框) ime (true, , 0, 0)",
    "填  另 乙 said [ok]",
  ])
}
