// Android's input method: its edits made on the host's copy of the field's words (MBView.MBInput), the field's whole
// state sent after each; and the keyboard put away by the person.

///|
fn ime_field(field : @ui.Field) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) { c.editor("field", font_size=10.0, field~) |> ignore },
    w=300.0,
    h=100.0,
    platform=2,
  )
}

///|
test "ime state: words and a selection taken as they are; a composition at the caret kept apart, as composed" {
  let field = @ui.Field::new()
  let t = ime_field(field)
  t.tap(50.0, 20.0)
  t.ime_state("你好 ", 3, 3)
  assert_eq(field.text(), "你好 ")
  assert_eq(field.selection(), (3, 3))
  // "shi" composed after it: not among the words yet; the host told the words without it, the caret before it
  t.ime_state("你好 shi", 6, 6, ca=3, cb=6)
  assert_eq(field.text(), "你好 ")
  assert_eq(t.ime(), (true, "你好 ", 3, 3))
  // committed
  t.ime_state("你好 是", 4, 4)
  assert_eq(field.text(), "你好 是")
  assert_eq(field.selection(), (4, 4))
  // a word composed again away from the end (the caret in it): kept apart where it is
  t.ime_state("你好 是", 2, 2, ca=0, cb=2)
  assert_eq(field.text(), " 是")
  // a composing region that does not hold the caret: words like the others
  t.ime_state("ab cd", 5, 5, ca=0, cb=2)
  assert_eq(field.text(), "ab cd")
  assert_eq(field.selection(), (5, 5))
}

///|
test "ime state: the keyboard put away lets go of the focus, what was composed kept; a tap takes it again" {
  let field = @ui.Field::new()
  let t = ime_field(field)
  t.tap(50.0, 20.0)
  t.ime_state("hi wor", 6, 6, ca=3, cb=6)
  assert_true(t.ime().0)
  t.keyboard_gone()
  assert_eq(field.text(), "hi wor")
  assert_false(t.ime().0)
  assert_true(t.focused() is None)
  t.tap(50.0, 20.0)
  assert_true(t.ime().0)
}
