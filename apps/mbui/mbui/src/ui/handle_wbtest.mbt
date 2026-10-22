// Android's caret handle (Compose's cursor handle): a tap that puts the caret in a field shows it under the caret;
// dragged, it moves the caret; what is typed lets it go.

///|
fn handle_tester(field : Field) -> Tester {
  Tester::new(
    fn(c) { c.editor("field", font_size=16.0, field~) |> ignore },
    w=300.0,
    h=200.0,
    platform=2,
  )
}

///|
test "handle: shown by a tap, under the caret; dragged, the caret goes with it; typing lets it go" {
  let field = Field::new()
  field.set("hello world")
  let t = handle_tester(field)
  t.tap(20.0, 10.0)
  t.draw()
  let st = g().editors.get(g().focus).unwrap()
  assert_true(st.handle_on)
  let before = field.selection().0
  // the finger on the handle's circle, moved right along the line
  let hx = st.handle_x
  let hy = st.handle_y + handle_r * 1.4
  t.drag(hx, hy, hx + 60.0, hy, steps=6)
  assert_true(field.selection().0 > before)
  assert_true(st.handle_on)
  t.type_text("!")
  assert_false(st.handle_on)
  // a tap on another place in it: shown again
  t.tap(60.0, 10.0)
  t.draw()
  assert_true(st.handle_on)
}

///|
test "handle: none off Android" {
  let field = Field::new()
  field.set("hello world")
  let t = Tester::new(fn(c) { c.editor("field", font_size=16.0, field~) |> ignore }, w=300.0, h=200.0)
  t.tap(20.0, 10.0)
  t.draw()
  assert_false(g().editors.get(g().focus).unwrap().handle_on)
}

///|
test "Android: a finger that moves on from a field leaves it be; one that lifts where it came down takes it" {
  let field = Field::new()
  field.set("hello world")
  let t = handle_tester(field)
  t.drag(40.0, 10.0, 40.0, 70.0, steps=5)
  assert_false(t.ime().0)
  t.tap(40.0, 10.0)
  assert_true(t.ime().0)
}

///|
test "Android: a tap on the field that has the focus says it to the host again (which asks for its keyboard again)" {
  let field = Field::new()
  field.set("hello world")
  let t = handle_tester(field)
  t.tap(40.0, 10.0)
  assert_true(t.ime().0)
  let told = fake.val.unwrap().ime_told
  // the same place: nothing of the field changed, and still said
  t.tap(40.0, 10.0)
  assert_true(fake.val.unwrap().ime_told > told)
}
