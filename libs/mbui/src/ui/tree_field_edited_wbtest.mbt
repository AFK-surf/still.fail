// What a field of the window's tree tells of the person's edits (ui's field's `edited`): each as it is made, a key, the
// input method's words once given, a paste, an undo; never what the app puts in it (Field::set, Field::follow).

///|
/// A window whose tree holds one field of `f`, focused, `edited` telling `told` its words as each edit makes them.
fn edited_field(f : Field, told : Array[String]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.width(Is(Some(200.0))) |> ignore
      field(h, f, font_size=10.0, max_lines=1, edited=fn(w) { told.push(w) }) |> ignore
    })
    |> ignore
  })
  t.draw()
  f.focus()
  t.draw()
  t
}

///|
test "a tree field's edited: told the person's edits as each is made, a key, the input method's words, a paste, an undo" {
  let f = Field::new()
  let told : Array[String] = []
  let t = edited_field(f, told)
  // (typed: the words the host gives, a hardware keyboard's or the input method's at once)
  t.type_text("ab")
  assert_eq(told, ["ab"])
  // (a key that edits)
  t.key(key_backspace)
  assert_eq(told, ["ab", "a"])
  // (the input method composing: nothing yet, its words not the field's till given; then given)
  t.compose("ni")
  assert_eq(told, ["ab", "a"])
  t.type_text("你")
  assert_eq(told, ["ab", "a", "a你"])
  // (pasted)
  t.paste("cd")
  assert_eq(told, ["ab", "a", "a你", "a你cd"])
  // (undone: the paste taken back)
  t.key(key_of_char('z'), mods=mod_cmd)
  assert_eq(told, ["ab", "a", "a你", "a你cd", "a你"])
  assert_eq(f.text(), "a你")
}

///|
test "a tree field's edited: never told the app's words, set or followed" {
  let f = Field::new()
  let told : Array[String] = []
  let t = edited_field(f, told)
  // (followed while it has no edit of the person's: the core's draft put in)
  f.follow("the core's draft")
  t.frame()
  assert_eq(f.text(), "the core's draft")
  f.set("from the app")
  t.frame()
  assert_eq(f.text(), "from the app")
  assert_eq(told, [])
  // (the person's edit after them: told, with the words as they are then)
  t.type_text("!")
  assert_eq(told, ["from the app!"])
}

///|
test "a tree field's edited: let go with its node, nothing told after" {
  let f = Field::new()
  let told : Array[String] = []
  let shown = @signals.signal(true)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.width(Is(Some(200.0))) |> ignore
      h.show(at_once=true, fn() { shown.get() }, fn(s) {
        field(s, f, font_size=10.0, max_lines=1, edited=fn(w) { told.push(w) }) |> ignore
      })
    })
    |> ignore
  })
  t.draw()
  f.focus()
  t.draw()
  t.type_text("a")
  assert_eq(told, ["a"])
  shown.set(false)
  t.frame()
  // (its editor no longer the tree's: what it told of edits gone with it)
  assert_true(f.st.on_change is None)
  assert_eq(told, ["a"])
}
