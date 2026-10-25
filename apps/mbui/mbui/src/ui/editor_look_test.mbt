// An editor's words drawn as the app says (Ctx::editor's `look`), and what it holds kept by the app (Field), read
// and written from anywhere: what a composer's marks need (a reference drawn in a colour, its brackets unseen, taken
// out whole by a backspace, put in when a core answers).

///|
test "look: the same letters in the same places, ranges of them in their own colours; the words themselves as typed" {
  let field = @ui.Field::new()
  let t = @ui.Tester::new(
    fn(c) {
      c.editor(
        "field",
        field~,
        font_size=10.0,
        color=0x000000FFL,
        look=fn(s) {
          // "ab" drawn "AB" in red
          let out = s.replace_all(old="ab", new="AB")
          let spans : Array[(Int, Int, Int64)] = []
          match s.find("ab") {
            Some(k) => spans.push((k, k + 2, 0xFF0000FFL))
            None => ()
          }
          (out, spans)
        },
      )
      |> ignore
    },
    w=300.0,
    h=100.0,
  )
  t.tap(50.0, 20.0)
  t.type_text("xaby")
  t.draw()
  assert_eq(field.text(), "xaby")
  let glyphs = t.drawn_glyphs()
  assert_eq(glyphs.length(), 4)
  assert_eq(glyphs.filter(fn(g) { g.2 == 0xFF0000FFL }).length(), 2)
  assert_eq(glyphs.filter(fn(g) { g.2 == 0x000000FFL }).length(), 2)
}

///|
/// Long enough for a tap's frames to be over (a few frames' time): what the tests wait for their field to be at rest.
let rest_ms : Double = 100.0

///|
test "a field the app keeps: typing writes it, the app's writes show, from within a scope or outside any frame" {
  let field = @ui.Field::new()
  let t = @ui.Tester::new(
    fn(c) { c.scope(7, fn() { c.editor("field", font_size=10.0, field~) |> ignore }) },
    w=300.0,
    h=100.0,
  )
  t.tap(50.0, 20.0)
  t.type_text("hello")
  assert_eq(field.text(), "hello")
  assert_eq(field.selection(), (5, 5))
  t.run_for(rest_ms)
  assert_true(t.at_rest(), msg=t.rest_why())
  // between frames (an answer come in): written to the field, not looked for where the editor is; the write asks for
  // the frame that draws it
  field.set("he world", caret=2)
  assert_false(t.at_rest())
  t.frame()
  let (_, words, _, _) = t.ime()
  assert_eq(words, "he world")
  t.type_text("y")
  assert_eq(field.text(), "hey world")
  assert_eq(field.selection(), (3, 3))
}

///|
test "another field given to the same editor: it shows that one, the first kept as it was" {
  let a = @ui.Field::new(text="one")
  let b = @ui.Field::new(text="two")
  let which = Ref(a)
  let t = @ui.Tester::new(fn(c) { c.editor("field", font_size=10.0, field=which.val) |> ignore }, w=300.0, h=100.0)
  t.tap(50.0, 20.0)
  t.type_text("!")
  assert_eq(a.text(), "one!")
  which.val = b
  t.draw()
  t.type_text("?")
  assert_eq(b.text(), "two?")
  assert_eq(a.text(), "one!")
}

///|
test "a field written from a fiber (after a sleep): a frame comes for it and draws it" {
  // how long the fiber sleeps before it writes
  let nap = 200
  let field = @ui.Field::new()
  let t = @ui.Tester::new(
    fn(c) {
      c.editor("field", font_size=10.0, field~) |> ignore
      c.effect("later", async fn(_s) {
        @effect.sleep(nap)
        field.set("from a fiber")
      })
    },
    w=300.0,
    h=100.0,
  )
  t.tap(50.0, 20.0)
  t.run_for(nap.to_double() + rest_ms)
  let (_, words, _, _) = t.ime()
  assert_eq(words, "from a fiber")
  t.run_for(rest_ms)
  assert_true(t.at_rest(), msg=t.rest_why())
}

///|
test "a field written with what it holds already: nothing to draw, no frame asked for" {
  let field = @ui.Field::new(text="same")
  let t = @ui.Tester::new(fn(c) { c.editor("field", font_size=10.0, field~) |> ignore }, w=300.0, h=100.0)
  t.run_for(rest_ms)
  assert_true(t.at_rest(), msg=t.rest_why())
  field.set("same")
  assert_true(t.at_rest(), msg=t.rest_why())
}

///|
test "panic: one Field given to two editors in one build stops the app, naming both" {
  let field = @ui.Field::new()
  let t = @ui.Tester::new(
    fn(c) {
      c.editor("one", font_size=10.0, field~) |> ignore
      c.editor("two", font_size=10.0, field~) |> ignore
    },
    w=300.0,
    h=100.0,
  )
  t.frame()
}

///|
test "a Field kept over one Tester's end (an app's own) and given to another editor by the next is no second editor" {
  let field = @ui.Field::new()
  let first = @ui.Tester::new(
    fn(c) { c.scope(1, fn() { c.editor("search", font_size=10.0, field~) |> ignore }) },
    w=300.0,
    h=100.0,
  )
  ignore(first)
  // a new run (its first frame drawn as it begins): its builds counted on from the last, not again from the first, so
  // the Field's last editor (the run before's, its build the same count in) is not this build's
  let next = @ui.Tester::new(
    fn(c) { c.scope(2, fn() { c.editor("search", font_size=10.0, field~) |> ignore }) },
    w=300.0,
    h=100.0,
  )
  next.frame()
}

///|
test "panic: one Field given to the same key's editors in two scopes (a list's rows) stops the app too" {
  let field = @ui.Field::new()
  let t = @ui.Tester::new(
    fn(c) {
      c.scope(1, fn() { c.editor("draft", font_size=10.0, field~) |> ignore })
      c.scope(2, fn() { c.editor("draft", font_size=10.0, field~) |> ignore })
    },
    w=300.0,
    h=100.0,
  )
  t.frame()
}

///|
test "a focused field's caret blinks till caret_blinks_for_ms after it last moved, then rests shown and asks nothing" {
  let field = @ui.Field::new()
  let t = @ui.Tester::new(
    fn(c) { c.editor("field", field~, font_size=10.0) |> ignore },
    w=300.0,
    h=100.0,
  )
  t.tap(50.0, 20.0)
  t.type_text("hi")
  t.draw()
  // shown as it was typed, hidden half a blink later, its next change waited for
  let shown = t.frame_hash()
  t.run_for(@ui.caret_blink_ms * 1.5)
  assert_true(t.frame_hash() != shown)
  assert_true(t.next_wake() is Some(_))
  // past caret_blinks_for_ms: shown, and nothing more to wait for
  t.run_for(@ui.caret_blinks_for_ms)
  assert_eq(t.frame_hash(), shown)
  assert_true(t.next_wake() is None, msg=t.rest_why())
  // a letter typed: it blinks again
  t.type_text("!")
  t.draw()
  assert_true(t.next_wake() is Some(_))
  assert_eq(field.text(), "hi!")
}
