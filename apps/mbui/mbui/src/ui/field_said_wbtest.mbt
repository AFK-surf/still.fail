// A Field's words followed (Field::text): what reads them told as each way of changing them changes them, typed,
// taken out, undone and done again, set by the app, with no frame drawn between.

///|
test "a field's words followed: what reads them told as they are typed, taken out, undone, done again and set, each as it comes, no frame between; not told where nothing changed" {
  let field = Field::new()
  let t = Tester::new(fn(c) { c.editor("field", field~, font_size=10.0) |> ignore }, w=300.0, h=100.0, platform=0)
  t.tap(50.0, 20.0)
  t.draw()
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(field.text()) })
  let at = fn(what : String) {
    match seen.last() {
      Some(s) => s
      None => "(none: \{what})"
    }
  }
  t.text_told("ab", t.time())
  assert_eq(at("typed"), "ab", msg="typed")
  t.key_told(key_code_backspace, 0, t.time())
  assert_eq(at("taken out"), "a", msg="taken out")
  t.key_told(key_of_char('z'), mod_cmd, t.time())
  assert_eq(at("undone"), field.st.text, msg="undone: as it holds")
  assert_true(at("undone") != "a", msg="undone: told otherwise")
  t.key_told(key_of_char('z'), mod_cmd | mod_shift_key, t.time())
  assert_eq(at("done again"), "a", msg="done again")
  field.set("set by the app")
  assert_eq(at("set"), "set by the app", msg="set")
  let told = seen.length()
  field.set("set by the app")
  assert_eq(seen.length(), told, msg="set the same: not told again")
  stop()
}

///|
test "a field set by the app with no frame and no event round it: what reads its words and its caret sees both as set, told once; taken, told once, empty" {
  let field = Field::new(text="abc")
  let seen : Array[(String, Int, Int)] = []
  let stop = @signals.effect(fn() {
    let (a, c) = field.selection()
    seen.push((field.text(), a, c))
  })
  field.set("x", caret=1)
  assert_eq(seen, [("abc", 3, 3), ("x", 1, 1)], msg="set: its words and caret as set, told once")
  let taken = field.take()
  assert_eq(taken, "x", msg="taken")
  assert_eq(seen, [("abc", 3, 3), ("x", 1, 1), ("", 0, 0)], msg="taken: told once, empty")
  stop()
}

///|
test "a field taken while the input method composes: what is composed not among its words till then; taken whole with it, what reads its words told once, empty, never with it put in on the way" {
  let field = Field::new()
  let t = Tester::new(fn(c) { c.editor("field", field~, font_size=10.0) |> ignore }, w=300.0, h=100.0, platform=0)
  t.tap(50.0, 20.0)
  t.draw()
  t.type_text("ab")
  t.compose("cd")
  assert_eq(field.text(), "ab", msg="composing: not among its words")
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(field.text()) })
  let taken = field.take()
  assert_eq(taken, "abcd", msg="taken whole, what was composed with it")
  assert_eq(seen, ["ab", ""], msg="told once, empty: \{seen}")
  stop()
}

///|
test "an editor's own state taken as a Field (Ctx::editor_field) after it was built: its words followed from then, told as they are typed and set with no frame between; taken again, the same words followed, not new ones" {
  let t = Tester::new(fn(c) { c.editor("own", font_size=10.0) |> ignore }, w=300.0, h=100.0, platform=0)
  t.tap(50.0, 20.0)
  t.draw()
  let field = t.ctx().editor_field("own")
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(field.text()) })
  t.text_told("ab", t.time())
  assert_eq(seen.last(), Some("ab"), msg="typed: told \{seen}")
  let again = t.ctx().editor_field("own")
  again.set("set through the other")
  assert_eq(seen.last(), Some("set through the other"), msg="set through the Field taken again: told to the first's \{seen}")
  field.set("x")
  assert_eq(seen.last(), Some("x"), msg="set: told \{seen}")
  stop()
}

///|
test "a code field's editor taken as a Field and followed: emptied as asked (clear_code_field), what reads its words told empty, not left with what was typed" {
  let t = Tester::new(fn(c) { c.code_field("code", length=4, autofocus=true) |> ignore }, w=300.0, h=100.0, platform=0)
  t.draw()
  t.draw()
  let field = t.ctx().editor_field("code")
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(field.text()) })
  t.text_told("12", t.time())
  assert_eq(field.text(), "12", msg="typed: \{seen}")
  t.ctx().clear_code_field("code")
  t.draw()
  assert_eq(field.text(), "", msg="emptied as asked: \{seen}")
  assert_eq(seen.last(), Some(""), msg="told empty: \{seen}")
  stop()
}
