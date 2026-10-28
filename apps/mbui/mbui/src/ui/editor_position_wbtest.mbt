///|
test "a field in a list row keeps its text origin when the pointer rebuilds the row" {
  let field = Field::new()
  let t = Tester::new(fn(c) {
    c.list("rows", 6, 120.0, fn(i) {
      c.column(h=Px(120.0), fn() {
        if i == 4 {
          c.editor("code", placeholder="Paste code", field~, plain=true) |> ignore
        } else {
          c.text("row " + i.to_string()) |> ignore
        }
      }) |> ignore
    }, stick_end=true) |> ignore
  }, w=600.0, h=400.0, platform=3)
  t.keep_parts(true)
  for (x, y) in [(300.0, 250.0), (590.0, 250.0), (300.0, 260.0), (590.0, 260.0)] {
    t.move(x, y)
    let c = g()
    let mut found = false
    for i in 0..<c.count {
      let n = c.nodes[i]
      if n.kind == kind_editor {
        found = true
        let st = c.editors.get(n.id).unwrap()
        assert_eq(st.ox, n.x + n.pad_l)
        assert_eq(st.oy, n.y + n.pad_t - st.scroll)
      }
    }
    assert_true(found)
  }
}

///|
test "placing a kept field at a new parent origin moves its words with its box" {
  let field = Field::new()
  let t = Tester::new(fn(c) {
    c.editor("code", placeholder="Paste code", field~) |> ignore
  }, w=600.0, h=400.0)
  t.frame()
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_editor {
      c.replace(i, 30.0, 70.0)
      assert_eq(field.st.ox, n.x + n.pad_l)
      assert_eq(field.st.oy, n.y + n.pad_t - field.st.scroll)
      c.shift(i, 40.0)
      assert_eq(field.st.oy, n.y + n.pad_t - field.st.scroll)
      return
    }
  }
  fail("the field was not built")
}
