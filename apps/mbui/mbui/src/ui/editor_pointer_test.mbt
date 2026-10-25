// A field under a mouse, as a Mac's and a browser's: a double click picks the word, a triple click the paragraph, a
// drag on from them widens by them; a click with Shift widens what is picked; and what the menu bar's editing items
// can do (@hostapi.edit_can). Words 10 high, Latin 5 across (editor_keys_test.mbt's keys_field).

///|
/// Where the first line's letter `i` is pressed in a keys_field whose caret's place at its start was (`x0`, `y0`, `h`):
/// on its left half, the caret going before it.
fn letter_at(x0 : Double, y0 : Double, h : Double, i : Int) -> (Double, Double) {
  (x0 + 5.0 * i.to_double() + 1.0, y0 + h / 2.0)
}

///|
test "a double click in a field picks the word there, a triple click its paragraph" {
  let (f, t) = keys_field("hello brave world\nnext one", 0)
  let (x0, y0, _, h) = t.ime_rect()
  let (x, y) = letter_at(x0, y0, h, 7)
  t.tap(x, y)
  assert_eq(f.selection(), (7, 7))
  t.tap(x, y)
  assert_eq(f.selection(), (6, 11))
  t.tap(x, y)
  assert_eq(f.selection(), (0, 17))
  // a click elsewhere: the caret again
  let (x, y) = letter_at(x0, y0, h, 2)
  t.tap(x, y)
  assert_eq(f.selection(), (2, 2))
}

///|
test "a drag on from a double click widens what is picked by words, either way" {
  let (f, t) = keys_field("hello brave world", 0)
  let (x0, y0, _, h) = t.ime_rect()
  let (x, y) = letter_at(x0, y0, h, 7)
  t.tap(x, y)
  let (x1, _) = letter_at(x0, y0, h, 13)
  t.hold_drag(x, y, x1, y)
  assert_eq(f.selection(), (6, 17))
  // (the button still down: on past where it began)
  let (x2, _) = letter_at(x0, y0, h, 1)
  t.move(x2, y)
  t.release(x2, y)
  assert_eq(f.selection(), (11, 0))
}

///|
test "a click with Shift widens what is picked to it, from where it was" {
  let (f, t) = keys_field("hello brave world", 0)
  let (x0, y0, _, h) = t.ime_rect()
  f.set(f.text(), caret=2)
  t.draw()
  let (x, y) = letter_at(x0, y0, h, 13)
  t.hold_mods(@ui.mod_shift_key)
  t.tap(x, y)
  t.hold_mods(0)
  assert_eq(f.selection(), (2, 13))
}

///|
test "a double click in a secret's field picks all of it, as a move by words goes over all of it" {
  let (f, t) = keys_field("hunter two", 0, secret=true)
  let (x0, y0, _, h) = t.ime_rect()
  let (x, y) = letter_at(x0, y0, h, 3)
  t.tap(x, y)
  t.tap(x, y)
  assert_eq(f.selection(), (0, 10))
}

///|
test "the menu bar's editing items can do what the focused field can: its edits to undo and do again among them" {
  let (f, t) = keys_field("ab", 2)
  let paste = @hostapi.text_menu_paste
  assert_eq(t.edit_can(), paste | @hostapi.text_menu_select_all)
  t.type_text("c")
  assert_eq(t.edit_can(), paste | @hostapi.text_menu_select_all | @hostapi.text_menu_undo)
  t.key(@ui.key_of_char('z'), mods=@ui.mod_cmd)
  assert_eq(f.text(), "ab")
  assert_eq(t.edit_can(), paste | @hostapi.text_menu_select_all | @hostapi.text_menu_redo)
  t.key(@ui.key_code_select_all)
  assert_eq(
    t.edit_can(),
    @hostapi.text_menu_cut | @hostapi.text_menu_copy | paste | @hostapi.text_menu_redo,
  )
  // while the input method composes: nothing to undo or do again
  t.compose("ni")
  assert_eq(t.edit_can() & (@hostapi.text_menu_undo | @hostapi.text_menu_redo), 0)
}

///|
test "with no field focused, the menu bar's editing items can do nothing" {
  let t = @ui.Tester::new(fn(c) { c.text("words", wrap=false) |> ignore }, w=200.0, h=100.0)
  t.draw()
  assert_eq(t.edit_can(), 0)
}
