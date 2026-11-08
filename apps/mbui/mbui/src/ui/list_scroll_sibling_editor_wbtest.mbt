///|
test "a focused editor beside a list stays editable when its rows scroll without layout" {
  let field = Field::new(text="draft")
  let rows : ListRows[Int] = ListRows::new()
  let t = Tester::new(fn(c) {
    c.column(w=Fill(1.0), h=Fill(1.0), fn() {
      let ids = Array::makei(30, fn(i) { i })
      let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
      c.list("rows", items.length(), 40.0, fn(k) {
        c.box(h=Px(40.0), fn() { c.text("row \{items[k]}", wrap=false) |> ignore }) |> ignore
      }, h=Px(160.0), rows_read=true, sized=rows.sized()) |> ignore
      c.editor("draft", placeholder="type here", field~, plain=true) |> ignore
    }) |> ignore
  }, w=300.0, h=220.0)
  t.check_looks(true)
  t.set_rows_on_pixels(true)
  t.draw()
  t.tap(20.0, 175.0)
  t.type_text("!")
  let draft = field.text()
  assert_true(draft.contains("!"), msg="the sibling field must be focused")
  let at = t.time()
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  t.frame_at(at + 16.0)
  let before = t.row(2).unwrap()
  let reason = Ref("")
  frame_hook.val = Some(fn() { reason.val = painted_why.val })
  t.wheel_told(100.0, 100.0, 0.0, 5.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  frame_hook.val = None
  assert_true(t.row(2).unwrap().1 < before.1, msg="the list must move")
  assert_eq(field.text(), draft, msg="scrolling must not change the sibling editor")
  t.type_text("?")
  assert_true(field.text().contains("?"), msg="the sibling editor must remain focused and editable")
  assert_eq(reason.val, "a list scrolled without changing its rows",
    msg="a stationary sibling editor should not force the list to be laid out")
}

///|
test "an editor inside a moving row still takes the complete layout path" {
  let field = Field::new(text="in a row")
  let rows : ListRows[Int] = ListRows::new()
  let t = Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      let item = items[k]
      c.box(h=Px(40.0), fn() {
        if item == 2 {
          c.editor("draft", field~, plain=true) |> ignore
        } else {
          c.text("row \{item}", wrap=false) |> ignore
        }
      }) |> ignore
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  t.frame_at(at + 16.0)
  let before = field.st.oy
  let layouts = @flex.computes()
  t.wheel_told(100.0, 100.0, 0.0, 5.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  assert_true(field.st.oy < before, msg="the moving editor's text origin must follow its row")
  assert_true(@flex.computes() > layouts, msg="a moving editor must take the complete layout path")
}
