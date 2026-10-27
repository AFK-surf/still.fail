// Android's words picked in a field by a finger (Compose's text field selection): a long press or a double tap picks
// the word there, its two handles drag its ends, the system's floating menu (@hostapi.text_menu) over it; the caret's
// handle tapped shows the menu for pasting.

///|
/// A field holding `words` on an Android host, and its Tester.
fn android_field(words : String) -> (@ui.Field, @ui.Tester) {
  let f = @ui.Field::new(text=words)
  let t = @ui.Tester::new(fn(c) { c.editor("e", field=f, font_size=10.0) |> ignore }, w=300.0, h=100.0, platform=2)
  t.draw()
  (f, t)
}

///|
test "a long press on a word picks it: its handles, the floating menu over it to cut, copy, paste, select all; felt" {
  let (f, t) = android_field("hello brave world")
  t.press_at(16.0, 15.0)
  t.run_for(@ui.long_press_ms)
  t.release(16.0, 15.0)
  assert_eq(f.selection(), (0, 5))
  let (shown, _, _, _, _, can) = t.text_menu()
  assert_true(shown)
  assert_eq(
    can,
    @hostapi.text_menu_cut | @hostapi.text_menu_copy | @hostapi.text_menu_paste | @hostapi.text_menu_select_all,
  )
  assert_eq(t.haptics(), [@ui.Haptic::LongPress])
  // copied from the menu: on the clipboard, the menu away, let go of with the caret at its end
  t.key(@ui.key_code_copy)
  assert_eq(t.clipboard(), "hello")
  assert_false(t.text_menu().0)
  assert_eq(f.selection(), (5, 5))
}

///|
test "a long press on an empty field: the caret there, the floating menu over it to paste" {
  let (f, t) = android_field("")
  t.press_at(16.0, 15.0)
  t.run_for(@ui.long_press_ms)
  t.release(16.0, 15.0)
  assert_eq(f.selection(), (0, 0))
  let (shown, _, _, _, _, can) = t.text_menu()
  assert_true(shown)
  assert_eq(can, @hostapi.text_menu_paste)
}

///|
test "a second tap soon after the first picks the word there" {
  let (f, t) = android_field("hello brave world")
  t.tap(16.0, 15.0)
  assert_eq(f.selection().0, f.selection().1)
  t.run_for(@ui.double_tap_ms / 2.0)
  t.tap(16.0, 15.0)
  assert_eq(f.selection(), (0, 5))
  assert_true(t.text_menu().0)
}

///|
test "a picked word's end handle dragged on: the selection goes with it, the menu back once it is let go" {
  let (f, t) = android_field("hello brave world")
  t.press_at(16.0, 15.0)
  t.run_for(@ui.long_press_ms)
  t.release(16.0, 15.0)
  // the end's handle: its tip at the foot of the picked word's end (where the caret is), its circle to the right
  let (x, y, _, h) = t.ime_rect()
  let r = 12.5
  t.press_at(x + r, y + h + r)
  assert_false(t.text_menu().0)
  t.move(x + r + 400.0, y + h + r)
  t.release(x + r + 400.0, y + h + r)
  assert_eq(f.selection(), (0, 17))
  assert_true(t.text_menu().0)
}

///|
test "the caret's handle tapped: the menu to paste or select all; all selected from it keeps the menu over all" {
  let (f, t) = android_field("hello")
  t.tap(16.0, 15.0)
  let (x, y, _, h) = t.ime_rect()
  // the handle's circle: its radius √2 under its tip, at the caret's foot
  t.tap(x, y + h + 12.5 * 1.4142135623730951)
  let (shown, _, _, _, _, can) = t.text_menu()
  assert_true(shown)
  assert_eq(can, @hostapi.text_menu_paste | @hostapi.text_menu_select_all)
  t.key(@ui.key_code_select_all)
  assert_eq(f.selection(), (0, 5))
  let (shown, _, _, _, _, can) = t.text_menu()
  assert_true(shown)
  assert_eq(can, @hostapi.text_menu_cut | @hostapi.text_menu_copy | @hostapi.text_menu_paste)
  // typed over: the menu away
  t.type_text("x")
  assert_false(t.text_menu().0)
  assert_eq(f.text(), "x")
}

///|
test "desktop: a field right clicked is told with where (its edit menu's) and focused; cut, copy, select all and paste act on it" {
  let f = @ui.Field::new(text="hello world")
  let told : Array[(Int, Double, Double)] = []
  let can = Ref(0)
  let edits : Array[(Int, String)] = []
  let t = @ui.Tester::new(
    fn(c) {
      c.editor("e", field=f, font_size=10.0) |> ignore
      match c.field_right_clicked() {
        Some(x) => told.push(x)
        None => ()
      }
      match told.last() {
        Some((id, _, _)) => {
          can.val = c.field_can(id)
          for e in edits {
            c.field_edit(id, e.0, paste=e.1)
          }
          edits.clear()
        }
        None => ()
      }
    },
    w=300.0,
    h=100.0,
  )
  t.draw()
  t.right_click(16.0, 15.0)
  assert_true(told.length() > 0)
  let (_, x, y) = told[0]
  assert_eq((x, y), (16.0, 15.0))
  assert_true(t.ctx().editor_focused("e"))
  // nothing picked: paste or select all
  assert_eq(can.val & (@hostapi.text_menu_cut | @hostapi.text_menu_copy), 0)
  edits.push((@hostapi.text_menu_select_all, ""))
  t.draw()
  t.draw()
  assert_eq(f.selection(), (0, 11))
  assert_true((can.val & @hostapi.text_menu_copy) != 0)
  edits.push((@hostapi.text_menu_copy, ""))
  t.draw()
  assert_eq(t.clipboard(), "hello world")
  edits.push((@hostapi.text_menu_paste, "bye"))
  t.draw()
  assert_eq(f.text(), "bye")
}
