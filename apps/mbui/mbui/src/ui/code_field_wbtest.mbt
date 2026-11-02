///|
/// The digits the code field's boxes show, first to last.
fn code_boxes() -> String {
  let b = StringBuilder()
  for i in 0..<g().count {
    if g().nodes[i].kind == kind_rich {
      b.write_string(g().nodes[i].text)
    }
  }
  b.to_string()
}

///|
/// The code field's boxes (those edged), as (x, edge colour), first to last.
fn code_edges() -> Array[(Double, Int64)] {
  let out = []
  for i in 0..<g().count {
    let n = g().nodes[i]
    if n.kind == kind_box && n.border_w > 0.0 {
      out.push((n.x, n.border_c))
    }
  }
  out
}

///|
fn code_view(handed : Array[String], wrong? : Bool = false, enabled? : Bool = true) -> (Ctx) -> Unit {
  fn(c) {
    c.column(w=Fill(1.0), h=Fill(1.0), fn() {
      if c.code_field("code", wrong~, enabled~) is Some(code) {
        handed.push(code)
      }
      c.spacer()
    })
    |> ignore
  }
}

///|
test "a code field asks the host for the digits keyboard" {
  let t = Tester::new(code_view([]), platform=2)
  t.frame()
  assert_true(t.ime().0)
  assert_eq(t.ime_action(), @hostapi.ime_action_number)
}

///|
test "a completed code field removed after verification lets go of the keyboard" {
  let shown = Ref(true)
  let handed : Array[String] = []
  let t = Tester::new(fn(c) {
    if shown.val {
      code_view(handed)(c)
    }
  }, platform=2)
  t.type_text("123456")
  assert_eq(handed, ["123456"])
  assert_true(t.ime().0)
  shown.val = false
  t.frame()
  assert_false(t.ime().0)
}

///|
test "removing a code field leaves the keyboard with another field that already took it" {
  let shown = Ref(true)
  let t = Tester::new(fn(c) {
    if shown.val {
      c.code_field("code") |> ignore
    }
    c.editor("next", max_lines=1) |> ignore
  }, platform=2)
  t.frame()
  assert_true(t.ime().0)
  t.ctx().focus_editor("next")
  shown.val = false
  t.frame()
  assert_true(t.ime().0)
  t.type_text("other")
  assert_eq(t.ime().1, "other")
}

///|
test "a code field: digits only, as many as it has boxes, the field taking the keys as it shows" {
  let handed = []
  let t = Tester::new(code_view(handed))
  t.type_text("1a2-3 ")
  assert_eq(code_boxes(), "123")
  assert_true(t.dump().contains("\"123\" caret=3"))
  t.type_text("45678")
  assert_eq(code_boxes(), "123456")
  assert_true(t.dump().contains("\"123456\" caret=6"))
  // a code pasted whole, its dash and spaces left out
  t.ctx().clear_code_field("code")
  t.frame()
  t.type_text(" 987-654 ")
  assert_eq(code_boxes(), "987654")
  assert_eq(handed, ["123456", "987654"])
}

///|
test "a code field: a complete code handed on once, however many frames, and again only once it changed" {
  let handed = []
  let t = Tester::new(code_view(handed))
  t.type_text("12345")
  // a whole blink of its caret, shown and hidden, drawn as it goes
  t.draw()
  t.run_for(caret_blink_ms * 2.0)
  assert_eq(handed, [])
  t.type_text("6")
  // a whole blink of its caret, shown and hidden, drawn as it goes
  t.draw()
  t.run_for(caret_blink_ms * 2.0)
  assert_eq(handed, ["123456"])
  // a seventh digit is no new code
  t.type_text("7")
  t.frame()
  assert_eq(handed, ["123456"])
  // a digit taken back and typed again is
  t.backspace()
  t.frame()
  t.type_text("6")
  t.frame()
  assert_eq(handed, ["123456", "123456"])
  t.backspace()
  t.type_text("9")
  // a whole blink of its caret, shown and hidden, drawn as it goes
  t.draw()
  t.run_for(caret_blink_ms * 2.0)
  assert_eq(handed, ["123456", "123456", "123459"])
}

///|
test "a code field: emptied as asked between frames, the same code typed again handed again" {
  let handed = []
  let t = Tester::new(code_view(handed))
  t.type_text("424242")
  assert_eq(handed, ["424242"])
  // (as an answer refusing it comes, between frames)
  t.ctx().clear_code_field("code")
  t.frame()
  assert_eq(code_boxes(), "")
  assert_true(t.dump().contains("\"\" caret=0"))
  t.frame()
  assert_eq(code_boxes(), "")
  t.type_text("424242")
  assert_eq(handed, ["424242", "424242"])
}

///|
test "a code field: the next box edged, all red while wrong and empty, nothing typed while it may not" {
  let handed = []
  let wrong = Ref(false)
  let enabled = Ref(true)
  let t = Tester::new(fn(c) { code_view(handed, wrong=wrong.val, enabled=enabled.val)(c) })
  let plain = 0x1D1D1F2EL
  let next = 0x1D1D1FFFL
  let red = 0xFF3B30FFL
  let edges = code_edges()
  assert_eq(edges.length(), 6)
  assert_eq(edges.map(fn(e) { e.1 }), [next, plain, plain, plain, plain, plain])
  // three and three: 8 between boxes, a room 8 wide between the groups (and the gaps either side of it)
  assert_eq(edges[1].0 - edges[0].0, 50.0)
  assert_eq(edges[3].0 - edges[2].0, 66.0)
  t.type_text("12")
  assert_eq(code_edges().map(fn(e) { e.1 }), [plain, plain, next, plain, plain, plain])
  t.type_text("3456")
  assert_eq(code_edges().map(fn(e) { e.1 }), [plain, plain, plain, plain, plain, next])
  // refused: red until a digit is typed
  wrong.val = true
  t.ctx().clear_code_field("code")
  t.frame()
  assert_eq(code_edges().map(fn(e) { e.1 }), [red, red, red, red, red, red])
  t.type_text("1")
  assert_eq(code_edges().map(fn(e) { e.1 }), [plain, next, plain, plain, plain, plain])
  // while it may not change (a code being checked), typing does nothing and no box is the next
  enabled.val = false
  t.frame()
  t.type_text("23456")
  t.frame()
  assert_eq(code_boxes(), "1")
  assert_true(t.dump().contains("\"1\" caret=1"))
  assert_eq(code_edges().map(fn(e) { e.1 }), [plain, plain, plain, plain, plain, plain])
  assert_eq(handed, ["123456"])
}

///|
/// The code field's boxes (those edged), as (x, y, width), first to last.
fn code_places() -> Array[(Double, Double, Double)] {
  let out = []
  for i in 0..<g().count {
    let n = g().nodes[i]
    if n.kind == kind_box && n.border_w > 0.0 {
      out.push((n.x, n.y, n.fw))
    }
  }
  out
}

///|
test "a code field narrower than its row of boxes: drawn smaller in one row, then a row for each group, never past its room" {
  // room for them all: as asked, in one row (6 × 42, 8 apart, 8 more between the groups: 300)
  let wide = Tester::new(code_view([]), w=390.0)
  wide.frame()
  let all = code_places()
  assert_eq(all.map(fn(p) { p.2 }), [42.0, 42.0, 42.0, 42.0, 42.0, 42.0])
  assert_true(all.iter().all(fn(p) { p.1 == all[0].1 }))
  // 270 wide (an iPhone Duo's outer screen): smaller, still in one row, inside it
  let narrow = Tester::new(code_view([]), w=270.0)
  narrow.frame()
  let some = code_places()
  assert_true(some.iter().all(fn(p) { p.1 == some[0].1 && p.2 < 42.0 && p.2 >= 42.0 * 0.8 }))
  assert_true(some[0].0 >= 0.0 && some[5].0 + some[5].2 <= 270.01)
  // 200 wide: 3 over 3, as large as the room lets them be
  let tight = Tester::new(code_view([]), w=200.0)
  tight.frame()
  let rows = code_places()
  assert_eq(rows.map(fn(p) { p.2 }), [42.0, 42.0, 42.0, 42.0, 42.0, 42.0])
  assert_true(rows[0].1 == rows[2].1 && rows[3].1 > rows[0].1 && rows[3].1 == rows[5].1)
  assert_true(rows[0].0 >= 0.0 && rows[2].0 + rows[2].2 <= 200.01)
}
