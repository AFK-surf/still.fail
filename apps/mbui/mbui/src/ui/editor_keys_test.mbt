// A field's keys for moving and deleting by words, to a line's ends, a paragraph's and all of it, as each system's own
// fields have them (a Mac's ⌥ and ⌘, Ctrl elsewhere, Android's Alt), and a Mac's text system's names for them (its
// host's edit keys). Words 10 high: Latin 5 across, Chinese 10; a field `w` wide holds `w` - 24 of them on a line.

///|
/// A field holding `words`, focused, the caret at `caret`, on system `platform`, and its Tester.
fn keys_field(
  words : String,
  caret : Int,
  platform? : Int = 0,
  w? : Double = 300.0,
  secret? : Bool = false,
) -> (@ui.Field, @ui.Tester) {
  let f = @ui.Field::new(text=words)
  let t = @ui.Tester::new(
    fn(c) { c.editor("e", field=f, font_size=10.0, enter_sends=false, secret~) |> ignore },
    w~,
    h=200.0,
    platform~,
  )
  t.draw()
  t.tap(14.0, 14.0)
  f.set(words, caret~)
  t.draw()
  (f, t)
}

///|
fn caret_of(f : @ui.Field) -> Int {
  f.selection().1
}

///|
test "a browser on a Mac types as a Mac: ⌥← a word back, ⌘← the line's start, ⌘Z undone; Ctrl+← nothing" {
  let f = @ui.Field::new(text="hello world")
  let t = @ui.Tester::new(
    fn(c) { c.editor("e", field=f, font_size=10.0, enter_sends=false) |> ignore },
    w=300.0,
    h=200.0,
    platform=4,
    keys=0,
  )
  t.draw()
  t.tap(14.0, 14.0)
  f.set("hello world", caret=11)
  t.draw()
  assert_eq(@ui.keys_system(), 0)
  t.key(@ui.key_code_left, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 6)
  t.key(@ui.key_code_left, mods=@ui.mod_ctrl)
  assert_eq(caret_of(f), 6)
  t.key(@ui.key_code_left, mods=@ui.mod_cmd)
  assert_eq(caret_of(f), 0)
  t.type_text("X")
  assert_eq(f.text(), "Xhello world")
  t.key(@ui.key_of_char('z'), mods=@ui.mod_cmd)
  assert_eq(f.text(), "hello world")
}

///|
test "a browser on Windows types as Windows: Ctrl+← a word back, ⌥← nothing" {
  let (f, t) = keys_field("hello world", 11, platform=4)
  assert_eq(@ui.keys_system(), 4)
  t.key(@ui.key_code_left, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 11)
  t.key(@ui.key_code_left, mods=@ui.mod_ctrl)
  assert_eq(caret_of(f), 6)
}

///|
test "⌘← ⌘→ on a Mac: to the ends of the line the caret shows on; where it wraps, its end shows at its end" {
  // ten on the first line, three on the next
  let (f, t) = keys_field("一二三四五六七八九十甲乙丙", 3, w=124.0)
  let (x0, y0, _, h) = t.ime_rect()
  t.key(@ui.key_code_right, mods=@ui.mod_cmd)
  assert_eq(caret_of(f), 10)
  // at the first line's end, not the next one's start (the same place in the words)
  let (x, y, _, _) = t.ime_rect()
  assert_eq(x, x0 + 70.0)
  assert_eq(y, y0)
  // again: there it stays
  t.key(@ui.key_code_right, mods=@ui.mod_cmd)
  assert_eq(caret_of(f), 10)
  assert_eq(t.ime_rect().1, y0)
  // back to the start of the line it shows on
  t.key(@ui.key_code_left, mods=@ui.mod_cmd)
  assert_eq(caret_of(f), 0)
  // from the second line: its start, shown there, then the end of all of it
  f.set(f.text(), caret=11)
  t.draw()
  t.key(@ui.key_code_left, mods=@ui.mod_cmd)
  assert_eq(caret_of(f), 10)
  let (x, y, _, _) = t.ime_rect()
  assert_eq(x, x0 - 30.0)
  assert_eq(y, y0 + h)
  t.key(@ui.key_code_right, mods=@ui.mod_cmd | @ui.mod_shift_key)
  assert_eq(f.selection(), (10, 13))
}

///|
test "⌥← ⌥→ on a Mac: by words, passing over what lies between them; with ⇧ picking" {
  let (f, t) = keys_field("hello brave world", 17)
  t.key(@ui.key_code_left, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 12)
  t.key(@ui.key_code_left, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 6)
  t.key(@ui.key_code_right, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 11)
  t.key(@ui.key_code_right, mods=@ui.mod_alt | @ui.mod_shift_key)
  assert_eq(f.selection(), (11, 17))
  // from what is picked, not widening: from its end the move goes towards
  t.key(@ui.key_code_left, mods=@ui.mod_alt)
  assert_eq(f.selection(), (6, 6))
  // marks between words are passed over as spaces are
  let (f, t) = keys_field("one, two", 3)
  t.key(@ui.key_code_right, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 8)
  t.key(@ui.key_code_left, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 5)
  t.key(@ui.key_code_left, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 0)
}

///|
test "⌥⌫ deletes the word before, ⌘⌫ to the line's start, at its start the line break before" {
  let (f, t) = keys_field("hello brave world", 17)
  t.key(@ui.key_code_backspace, mods=@ui.mod_alt)
  assert_eq(f.text(), "hello brave ")
  assert_eq(caret_of(f), 12)
  let (f, t) = keys_field("one\ntwo three", 13)
  t.key(@ui.key_code_backspace, mods=@ui.mod_cmd)
  assert_eq(f.text(), "one\n")
  t.key(@ui.key_code_backspace, mods=@ui.mod_cmd)
  assert_eq(f.text(), "one")
  assert_eq(caret_of(f), 3)
}

///|
test "⌥↑ ⌥↓ on a Mac: to a paragraph's ends, the one before's or after's from there; ⌘↑ ⌘↓ to the ends of all of it" {
  let (f, t) = keys_field("ab\ncd\nef", 4)
  t.key(@ui.key_code_up, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 3)
  t.key(@ui.key_code_up, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 0)
  t.key(@ui.key_code_down, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 2)
  t.key(@ui.key_code_down, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 5)
  t.key(@ui.key_code_down, mods=@ui.mod_cmd)
  assert_eq(caret_of(f), 8)
  t.key(@ui.key_code_up, mods=@ui.mod_cmd | @ui.mod_shift_key)
  assert_eq(f.selection(), (8, 0))
}

///|
test "a Mac's text commands (its host's edit keys) do the same on every system" {
  let (f, t) = keys_field("ab cd\nef gh", 1, platform=3)
  t.key(@ui.key_code_word_on)
  assert_eq(caret_of(f), 2)
  t.key(@ui.key_code_line_end)
  assert_eq(caret_of(f), 5)
  t.key(@ui.key_code_text_end)
  assert_eq(caret_of(f), 11)
  t.key(@ui.key_code_paragraph_start)
  assert_eq(caret_of(f), 6)
  t.key(@ui.key_code_paragraph_back, mods=@ui.mod_shift_key)
  assert_eq(f.selection(), (6, 0))
  t.key(@ui.key_code_text_start)
  // ⌃K: to the paragraph's end, at its end the line break
  t.key(@ui.key_code_delete_paragraph_on)
  assert_eq(f.text(), "\nef gh")
  t.key(@ui.key_code_delete_paragraph_on)
  assert_eq(f.text(), "ef gh")
  t.key(@ui.key_code_text_end)
  t.key(@ui.key_code_delete_word_back)
  assert_eq(f.text(), "ef ")
}

///|
test "on Windows: Ctrl+→ to the next word's start, Ctrl+← back by words, Home End to the line's ends, Ctrl+⌫ a word" {
  let (f, t) = keys_field("hello brave world", 0, platform=3)
  t.key(@ui.key_code_right, mods=@ui.mod_ctrl)
  assert_eq(caret_of(f), 6)
  t.key(@ui.key_code_right, mods=@ui.mod_ctrl)
  assert_eq(caret_of(f), 12)
  t.key(@ui.key_code_left, mods=@ui.mod_ctrl)
  assert_eq(caret_of(f), 6)
  t.key(@ui.key_code_end)
  assert_eq(caret_of(f), 17)
  t.key(@ui.key_code_home)
  assert_eq(caret_of(f), 0)
  t.key(@ui.key_code_end, mods=@ui.mod_ctrl)
  t.key(@ui.key_code_backspace, mods=@ui.mod_ctrl)
  assert_eq(f.text(), "hello brave ")
  // Home and End by the line shown, Ctrl+Home to the start of all of it
  let (f, t) = keys_field("一二三四五六七八九十甲乙丙", 12, platform=3, w=124.0)
  t.key(@ui.key_code_home)
  assert_eq(caret_of(f), 10)
  t.key(@ui.key_code_home, mods=@ui.mod_ctrl)
  assert_eq(caret_of(f), 0)
  t.key(@ui.key_code_end)
  assert_eq(caret_of(f), 10)
}

///|
test "on Android: Ctrl+← Ctrl+→ by words, Alt+← Alt+→ to the line's ends, Alt+⌫ deleting to its start" {
  let (f, t) = keys_field("hello brave world", 8, platform=2)
  t.key(@ui.key_code_right, mods=@ui.mod_ctrl)
  assert_eq(caret_of(f), 11)
  t.key(@ui.key_code_right, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 17)
  t.key(@ui.key_code_left, mods=@ui.mod_ctrl)
  assert_eq(caret_of(f), 12)
  t.key(@ui.key_code_backspace, mods=@ui.mod_alt)
  assert_eq(f.text(), "world")
}

///|
test "a key with other keys held than its system's moves nothing" {
  let (f, t) = keys_field("hello brave world", 8)
  t.key(@ui.key_code_left, mods=@ui.mod_cmd | @ui.mod_alt)
  t.key(@ui.key_code_right, mods=@ui.mod_ctrl | @ui.mod_alt)
  t.key(@ui.key_code_backspace, mods=@ui.mod_ctrl | @ui.mod_cmd)
  assert_eq(f.text(), "hello brave world")
  assert_eq(caret_of(f), 8)
}

///|
test "a secret's words are one: ⌥← goes to its start" {
  let (f, t) = keys_field("hunter two", 10, secret=true)
  t.key(@ui.key_code_left, mods=@ui.mod_alt)
  assert_eq(caret_of(f), 0)
}

///|
test "↓ to past the end of a line that wraps into the next: the caret shows at that line's end, ↓ again the next" {
  // ten Chinese on the first line; "ab " on the second, the twenty c's after it on the third
  let (f, t) = keys_field("一二三四五六七八九十ab " + String::make(20, 'c'), 9, w=124.0)
  let (x0, y0, _, h) = t.ime_rect()
  t.key(@ui.key_code_down)
  assert_eq(caret_of(f), 13)
  let (x, y, _, _) = t.ime_rect()
  assert_eq(y, y0 + h)
  assert_eq(x, x0 - 90.0 + 15.0)
  t.key(@ui.key_code_down)
  assert_eq(caret_of(f), 31)
  assert_eq(t.ime_rect().1, y0 + 2.0 * h)
}

///|
test "the pointer past the end of a line that wraps into the next puts the caret at that line's end" {
  let (f, t) = keys_field("一二三四五六七八九十甲乙丙", 0, w=124.0)
  let (x0, y0, _, _) = t.ime_rect()
  t.tap(119.0, y0 + 2.0)
  assert_eq(caret_of(f), 10)
  let (x, y, _, _) = t.ime_rect()
  assert_eq(x, x0 + 100.0)
  assert_eq(y, y0)
}
