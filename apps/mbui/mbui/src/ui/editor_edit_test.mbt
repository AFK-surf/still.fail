// A field's edits by the person told as each is made (Ctx::editor's `on_edit`): its words and selection before and
// after, and what made it (keys, a paste or words let go on it, an undo, the pointer); the app's own (Field::set) not
// told. Words 10 high, Latin 5 across (editor_keys_test.mbt's keys_field).

///|
test "a field's edits told as the person makes each (on_edit): the pointer's caret, keys typed and moving it, words let go on it, an undo; the app's own not" {
  let f = @ui.Field::new(text="ab")
  let edits : Array[(String, (Int, Int), String, (Int, Int), @ui.FieldEditBy)] = []
  let t = @ui.Tester::new(
    fn(c) {
      c.editor(
        "e",
        field=f,
        placeholder="the field",
        font_size=10.0,
        plain=true,
        enter_sends=false,
        on_edit=fn(e) { edits.push((e.was, e.was_selection, e.now, e.selection, e.by)) },
      )
      |> ignore
    },
    w=300.0,
    h=100.0,
  )
  t.draw()
  let (ex, ey, _, eh) = t.rect_of("the field").unwrap()
  // (its caret put at its start)
  t.tap(ex + 1.0, ey + eh / 2.0)
  t.type_text("x")
  t.key(@ui.key_code_right)
  // (between its `a` and its `b`)
  t.drop_words(ex + 10.0, ey + eh / 2.0, "cd")
  t.frame()
  t.key(@ui.key_of_char('z'), mods=@ui.mod_cmd)
  f.set("abc")
  t.frame()
  assert_eq(edits, [
    ("ab", (2, 2), "ab", (0, 0), Pointed),
    ("ab", (0, 0), "xab", (1, 1), Typed),
    ("xab", (1, 1), "xab", (2, 2), Typed),
    ("xab", (2, 2), "xacdb", (4, 4), Pasted),
    ("xacdb", (4, 4), "xab", (2, 2), Undone),
  ])
}

///|
test "what an edit changed of a field's words (words_changed, FieldEdit::span): where it began, the end of what it took, the end of what it put in" {
  assert_eq(@ui.words_changed("hello world", "hello brave world"), (6, 6, 12))
  assert_eq(@ui.words_changed("abc", "ac"), (1, 2, 1))
  assert_eq(@ui.words_changed("same", "same"), (4, 4, 4))
  let e : @ui.FieldEdit = { was: "ab", was_selection: (2, 2), now: "abcd", selection: (4, 4), by: Pasted }
  assert_eq(e.span(), (2, 2, 4))
}

///|
test "what the app puts in a field as the pointer's press answers (Field::set, its caret with it) is no one's edit: not told the pointer's, nor any; a tap in it after, the pointer's" {
  let f = @ui.Field::new(text="ab")
  let edits : Array[(String, (Int, Int), String, (Int, Int), @ui.FieldEditBy)] = []
  let t = @ui.Tester::new(
    fn(c) {
      c.editor(
        "e",
        field=f,
        placeholder="the field",
        font_size=10.0,
        plain=true,
        enter_sends=false,
        on_edit=fn(e) { edits.push((e.was, e.was_selection, e.now, e.selection, e.by)) },
      )
      |> ignore
      let put = c.id("put")
      c.box(id=put, fn() { c.text("put it in") |> ignore }) |> ignore
      c.on_press(put, fn() { f.set("a chat picked") })
    },
    w=300.0,
    h=100.0,
  )
  t.draw()
  let (bx, by, bw, bh) = t.rect_of("put it in").unwrap()
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  assert_eq(f.text(), "a chat picked")
  assert_eq(edits, [])
  let (ex, ey, _, eh) = t.rect_of("the field").unwrap()
  t.tap(ex + 1.0, ey + eh / 2.0)
  assert_eq(edits, [("a chat picked", (13, 13), "a chat picked", (0, 0), Pointed)])
}
