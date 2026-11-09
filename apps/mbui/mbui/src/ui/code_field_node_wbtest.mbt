// A code field as a node of the window's tree (code_field_node): digits only, as many as its boxes; the code told once
// it is complete and again only once it changed; emptied by what holds it, told again; nothing typed while it is off;
// its boxes in one row where the room has it, a row a group where not, from the room it is given.

///|
/// A window `w` wide whose tree holds one code field of `f` in a box as wide, `told` the codes it tells.
fn code_node_window(
  f : Field,
  told : Array[String],
  w? : Double = 390.0,
  enabled? : () -> Bool = fn() { true },
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w~, h=400.0, platform=2)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.width(Is(Some(w))) |> ignore
      code_field_node(h, f, fn(code) { told.push(code) }, label="安全码", enabled~) |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// The digits its boxes show, each with where it is drawn (its words' top left), first to last.
fn code_node_digits(t : Tester) -> Array[(String, Double, Double)] {
  t.words().filter(fn(w) { w.0.length() == 1 && w.0[0] >= '0' && w.0[0] <= '9' }).map(fn(w) { (w.0, w.1, w.2) })
}

///|
test "code field node: it takes the keys and the digits keyboard as it is made" {
  let f = Field::new()
  let t = code_node_window(f, [])
  assert_true(f.focused())
  assert_true(t.ime().0)
  assert_eq(t.ime_action(), @hostapi.ime_action_number)
}

///|
test "code field node: digits only, as many as its boxes, each in its box; the code told once, as it is complete" {
  let f = Field::new()
  let told : Array[String] = []
  let t = code_node_window(f, told)
  t.type_text("12-3 4")
  t.draw()
  assert_eq(f.text(), "1234")
  assert_eq(told, [])
  t.type_text("5678")
  t.draw()
  assert_eq(f.text(), "123456")
  assert_eq(told, ["123456"])
  assert_eq(code_node_digits(t).map(fn(d) { d.0 }), ["1", "2", "3", "4", "5", "6"])
  // (nothing more taken, nothing told again)
  t.type_text("9")
  assert_eq(f.text(), "123456")
  assert_eq(told, ["123456"])
}

///|
test "code field node: a digit taken back and typed again is told again; emptied by what holds it, the same code too" {
  let f = Field::new()
  let told : Array[String] = []
  let t = code_node_window(f, told)
  t.type_text("123456")
  t.key(key_backspace)
  t.type_text("6")
  assert_eq(told, ["123456", "123456"])
  // (refused: emptied for the next try, the same typed again told)
  f.set("")
  t.draw()
  assert_eq(code_node_digits(t), [])
  t.type_text("123456")
  assert_eq(told, ["123456", "123456", "123456"])
}

///|
test "code field node: while it is off, typing changes nothing" {
  let f = Field::new()
  let told : Array[String] = []
  let on = @signals.signal(true)
  let t = code_node_window(f, told, enabled=fn() { on.get() })
  t.type_text("12")
  on.set(false)
  t.draw()
  t.type_text("3456")
  t.draw()
  assert_eq(f.text(), "12")
  assert_eq(told, [])
}

///|
test "code field node: one row where its room has it, smaller where it must; a row a group where even that is too wide" {
  // (one row: 6 × 42 + 6 × 8 + 8 = 308 wide)
  let f = Field::new(text="123456")
  let t = code_node_window(f, [], w=390.0)
  let wide = code_node_digits(t)
  assert_eq(wide.length(), 6)
  assert_true(wide.iter().all(fn(d) { d.2 == wide[0].2 }))
  // (narrower than that, wider than 0.8 of it: one row still, its boxes closer)
  let f = Field::new(text="123456")
  let t = code_node_window(f, [], w=280.0)
  let smaller = code_node_digits(t)
  assert_true(smaller.iter().all(fn(d) { d.2 == smaller[0].2 }))
  assert_true(smaller[5].1 - smaller[0].1 < wide[5].1 - wide[0].1)
  // (narrower than 0.8 of it: three over three)
  let f = Field::new(text="123456")
  let t = code_node_window(f, [], w=200.0)
  let rows = code_node_digits(t)
  assert_eq(rows[0].2, rows[2].2)
  assert_true(rows[3].2 > rows[0].2)
  assert_eq(rows[3].1, rows[0].1)
}
