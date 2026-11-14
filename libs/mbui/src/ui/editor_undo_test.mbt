// A field's edits undone and done again (editor_undo.mbt): ⌘Z and ⇧⌘Z on a Mac, Ctrl+Z and Ctrl+Y elsewhere; a run
// of typing one step, a paste and a cut each one of their own, the app's words letting go of what was kept.

///|
/// ⌘Z (Ctrl+Z off Apple's systems) pressed, and ⇧⌘Z.
fn undo(t : @ui.Tester, platform? : Int = 0) -> Unit {
  t.key(@ui.key_of_char('z'), mods=if platform == 0 { @ui.mod_cmd } else { @ui.mod_ctrl })
}

///|
fn redo(t : @ui.Tester) -> Unit {
  t.key(@ui.key_of_char('z'), mods=@ui.mod_cmd | @ui.mod_shift_key)
}

///|
fn type_each(t : @ui.Tester, words : String) -> Unit {
  for ch in words {
    t.type_text(ch.to_string())
  }
}

///|
test "⌘Z on a Mac: a run of typing undone at once, the caret where it began; ⇧⌘Z types it again" {
  let (f, t) = keys_field("go ", 3)
  type_each(t, "hello")
  // a deletion at the caret is typing too, and the new line
  t.key(@ui.key_code_backspace)
  t.key(@ui.key_code_enter)
  type_each(t, "p!")
  assert_eq(f.text(), "go hell\np!")
  undo(t)
  assert_eq(f.text(), "go ")
  assert_eq(f.selection(), (3, 3))
  redo(t)
  assert_eq(f.text(), "go hell\np!")
  assert_eq(f.selection(), (10, 10))
  // none left to do again, none before the typing to undo: nothing
  redo(t)
  assert_eq(f.text(), "go hell\np!")
  undo(t)
  undo(t)
  assert_eq(f.text(), "go ")
}

///|
test "typing after the caret was moved, or over what is picked, is a step of its own" {
  let (f, t) = keys_field("", 0)
  type_each(t, "one")
  t.key(@ui.key_code_left)
  type_each(t, "X")
  t.key(@ui.key_code_select_all)
  type_each(t, "two")
  assert_eq(f.text(), "two")
  undo(t)
  assert_eq(f.text(), "onXe")
  assert_eq(f.selection(), (0, 4))
  undo(t)
  assert_eq(f.text(), "one")
  assert_eq(f.selection(), (2, 2))
  undo(t)
  assert_eq(f.text(), "")
}

///|
test "a paste and a cut are each a step of their own; undoing a cut picks what it took again" {
  let (f, t) = keys_field("", 0)
  type_each(t, "ab")
  t.paste("XY")
  type_each(t, "c")
  t.key(@ui.key_code_select_all)
  t.key(@ui.key_code_cut)
  assert_eq(f.text(), "")
  undo(t)
  assert_eq(f.text(), "abXYc")
  assert_eq(f.selection(), (0, 5))
  undo(t)
  assert_eq(f.text(), "abXY")
  undo(t)
  assert_eq(f.text(), "ab")
  undo(t)
  assert_eq(f.text(), "")
  // and back again, one by one
  redo(t)
  redo(t)
  assert_eq(f.text(), "abXY")
}

///|
test "an edit after an undo lets go of what was undone" {
  let (f, t) = keys_field("", 0)
  type_each(t, "ab")
  undo(t)
  type_each(t, "c")
  redo(t)
  assert_eq(f.text(), "c")
  undo(t)
  assert_eq(f.text(), "")
}

///|
test "words the app writes in the field let go of the edits kept: ⌘Z does not bring back what was sent" {
  let (f, t) = keys_field("", 0)
  type_each(t, "sent")
  assert_eq(f.take(), "sent")
  t.draw()
  undo(t)
  assert_eq(f.text(), "")
  type_each(t, "ab")
  f.set("put back")
  t.draw()
  undo(t)
  assert_eq(f.text(), "put back")
  // the caret alone moved by the app keeps them
  type_each(t, "!")
  f.set(f.text(), caret=0)
  t.draw()
  undo(t)
  assert_eq(f.text(), "put back")
}

///|
test "what an input method composes and commits is typing; ⌘Z while it composes is the input method's" {
  let (f, t) = keys_field("", 0)
  t.compose("ni")
  t.type_text("你")
  t.compose("hao")
  t.type_text("好")
  t.compose("a")
  undo(t)
  assert_eq(f.text(), "你好")
  t.ime_finish()
  assert_eq(f.text(), "你好a")
  undo(t)
  assert_eq(f.text(), "")
}

///|
test "Ctrl+Z off Apple's systems, Ctrl+Y and Ctrl+Shift+Z doing it again; ⌘Z there is no undo" {
  let (f, t) = keys_field("", 0, platform=3)
  type_each(t, "ab")
  t.key(@ui.key_of_char('z'), mods=@ui.mod_cmd)
  assert_eq(f.text(), "ab")
  undo(t, platform=3)
  assert_eq(f.text(), "")
  t.key(@ui.key_of_char('y'), mods=@ui.mod_ctrl)
  assert_eq(f.text(), "ab")
  undo(t, platform=3)
  t.key(@ui.key_of_char('z'), mods=@ui.mod_ctrl | @ui.mod_shift_key)
  assert_eq(f.text(), "ab")
}

///|
test "⌘Z with a field focused is the field's, not the app's shortcut; with none, the app's" {
  let seen : Array[String] = []
  let t = @ui.Tester::new(
    fn(c) {
      if c.shortcut('z') {
        seen.push("cmd-z")
      }
      c.editor("field", placeholder="words") |> ignore
    },
    w=400.0,
    h=300.0,
    platform=0,
  )
  undo(t)
  let (fx, fy) = t.find("words").unwrap()
  t.tap(fx, fy)
  undo(t)
  assert_eq(seen, ["cmd-z"])
}
