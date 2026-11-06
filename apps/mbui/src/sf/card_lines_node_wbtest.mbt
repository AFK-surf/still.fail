// A card's retained words: their order, room, styles and lifetime as the card changes.

///|
fn card_line_drawn(words : String) -> @view.Drawn raise {
  let drawn = @ui.view_tree().unwrap().drawn()
  match drawn.search_by(fn(d) { d.words == words }) {
    Some(i) => drawn[i]
    None => fail("card words not drawn: \{words}")
  }
}

///|
test "card lines update their four texts and omit empty lines without room" {
  let title = @signals.signal("Title")
  let words = @signals.signal("Description")
  let note = @signals.signal("Note")
  let bad = @signals.signal("Problem")
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=300.0, platform=2)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    card_lines_node(root, fn() { title.get() }, words=fn() { words.get() }, note=fn() { note.get() }, bad=fn() { bad.get() })
  })
  t.draw()
  let a = card_line_drawn("Title")
  let b = card_line_drawn("Description")
  let c = card_line_drawn("Note")
  let d = card_line_drawn("Problem")
  assert_eq((b.y - a.y - a.h, c.y - b.y - b.h, d.y - c.y - c.h), (2.0, 2.0, 2.0))
  assert_eq((a.words_look.weight, b.words_look.weight), (600, 400))
  assert_eq((a.ink, b.ink, c.ink, d.ink), (@ui.style_ink(desk_strong), @ui.style_ink(desk_words), @ui.style_ink(desk_muted), @ui.style_ink(desk_note_bad)))
  set_dark(Some(true))
  t.draw()
  let dark = card_line_drawn("Problem")
  assert_true(dark.ink != d.ink)
  assert_eq(dark.ink, @ui.style_ink(desk_note_bad))
  set_dark(None)
  title.set("新标题")
  words.set("")
  note.set("新提示")
  bad.set("")
  t.draw()
  let a = card_line_drawn("新标题")
  let c = card_line_drawn("新提示")
  assert_eq(c.y - a.y - a.h, 2.0)
  assert_true(!t.words().any(fn(w) { w.0 == "Description" || w.0 == "Note" || w.0 == "Problem" }))
  title.set("")
  note.set("")
  words.set("Only words")
  t.draw()
  assert_eq(t.words().map(fn(w) { w.0 }), ["Only words"])
}

///|
test "a card title keeps its retained action beside it across changes and releases it when the title disappears" {
  for scale in [1.0, 2.0] {
    let title = @signals.signal("A title long enough to give way to its action")
    let hits = Ref(0)
    let made = Ref(0)
    let action : Ref[@view.View?] = Ref(None)
    let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=300.0, platform=0)
    t.set_font_scale(scale)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      card_lines_node(root, fn() { title.get() }, title_after=fn(a) {
        made.val += 1
        action.val = Some(a)
        a.width(Is(Some(48.0))).height(Is(Some(24.0))).says(Is(Some(@view.said(Button, label="Action")))) |> ignore
        presses_node(a, fn() { hits.val += 1 })
      })
    })
    t.draw()
    let heading = card_line_drawn(title.get())
    let (x, y, w, h) = action.val.unwrap().rect()
    assert_true(heading.x + heading.w + 8.0 <= x + 0.01, msg="title and action overlap at \{scale}")
    assert_true(x + w <= 200.01 && (heading.y + heading.h / 2.0 - y - h / 2.0).abs() < 0.01)
    t.tap(x + w / 2.0, y + h / 2.0)
    assert_eq(hits.val, 1)
    t.act(Button, Focus, label="Action")
    t.enter()
    let kept = action.val.unwrap()
    title.set("Changed title")
    t.draw()
    assert_eq((made.val, kept.alive(), t.focused().map(fn(s) { s.label })), (1, true, Some("Action")))
    t.enter()
    title.set("")
    t.draw()
    assert_true(!kept.alive())
    assert_eq(t.focused().map(fn(s) { s.label }), None)
    title.set("Back")
    t.draw()
    assert_eq(made.val, 2)
    t.act(Button, Activate, label="Action")
    assert_eq(hits.val, 4)
  }
}

///|
test "card lines take the remaining width in a row without growing taller in a column" {
  let marker : Ref[@view.View?] = Ref(None)
  let end : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=300.0, platform=2)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(column) {
      column.height(Is(Some(200.0))).gap(Is(14.0)) |> ignore
      card_lines_node(column, fn() { "Column" })
      marker.val = Some(column.box(fn(m) { m.height(Is(Some(10.0))) |> ignore }))
    }) |> ignore
    root.box(fn(row) {
      row.row(Is(true)).width(Is(Some(200.0))).gap(Is(12.0)) |> ignore
      card_lines_node(row, fn() { "Row" }, in_row=true)
      end.val = Some(row.box(fn(e) { e.width(Is(Some(48.0))).height(Is(Some(24.0))) |> ignore }))
    }) |> ignore
  })
  t.draw()
  let heading = card_line_drawn("Column")
  let (_, y, _, _) = marker.val.unwrap().rect()
  let (x, _, _, _) = end.val.unwrap().rect()
  assert_eq(y, heading.y + heading.h + 14.0)
  assert_eq(x, 152.0)
}
