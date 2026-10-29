///|
test "pasting a long code in a one-line field scrolls sideways and keeps all its words" {
  let field = Field::new()
  let t = Tester::new(fn(c) {
    c.editor("code", field~, max_lines=1, plain=true, font_size=10.0) |> ignore
  }, w=120.0, h=100.0, platform=0)
  t.keep_parts(true)
  t.draw()
  t.tap(10.0, 5.0)
  let code = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  t.paste(code)
  let st = field.st
  assert_eq(st.text, code)
  assert_eq(st.tl.unwrap().line_start.length(), 1)
  assert_eq(st.scroll, 0.0)
  assert_true(st.scroll_x > 0.0)
  let (cx, _) = st.place_of(st.tl.unwrap(), st.caret)
  assert_true(st.ox + cx <= 120.0)
  assert_true(st.ox + cx > 100.0)
  t.key(key_code_left, mods=mod_cmd)
  assert_eq(st.caret, 0)
  assert_eq(st.scroll_x, 0.0)
  t.key(key_code_right, mods=mod_cmd)
  assert_eq(st.caret, code.length())
  assert_true(st.scroll_x > 0.0)
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_editor {
      c.replace(i, 30.0, 70.0)
      assert_eq(st.ox, n.x + n.pad_l - st.scroll_x)
      c.moved_shift(i, 20.0, 10.0)
      assert_eq(st.ox, n.x + n.pad_l - st.scroll_x)
      assert_eq(st.oy, n.y + n.pad_t)
    }
  }
  field.set("")
  t.draw()
  assert_eq(st.scroll_x, 0.0)
}

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
