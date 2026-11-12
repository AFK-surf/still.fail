// A field with the focus no longer shown (what shows it, a show of the tree's or an old view's `if`, now none): the
// focus is not left in it (the one rule: it is only in what shows); nothing typed goes into it, its input method put
// away. The tree's field and an old view's alike.

///|
/// A window holding a field of `f`, the tree's (`tree`) or an old view's, while `on`; tapped to take the focus, "a"
/// typed, then `on` none: what the host's input method is told then, and the field's words after "b" is typed.
fn field_gone(tree : Bool, platform : Int) -> ((Bool, String, Int, Int), String) {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let f = Field::new()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform~)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))).height(Is(Some(20.0))) |> ignore
      if tree {
        h.show(fn() { on.get() }, fn(v) {
          field(v, f, label="字", font_size=10.0, max_lines=1) |> ignore
        })
      } else {
        old(h, fn(c) {
          c.box(w=Px(200.0), h=Px(20.0), fn() {
            if on.get() {
              c.editor("e", field=f, font_size=10.0, max_lines=1, plain=true) |> ignore
            }
          })
          |> ignore
        })
        .grow(Is(1.0))
        |> ignore
      }
    })
    |> ignore
  })
  t.draw()
  t.tap(40.0, 30.0)
  t.draw()
  t.type_text("a")
  t.draw()
  guard f.text() == "a" else { @halt.saying("tree \{tree}, platform \{platform}: not typed into as it shows: \{f.text()}") }
  on.set(false)
  t.draw()
  t.draw()
  let ime = t.ime()
  t.type_text("b")
  t.draw()
  (ime, f.text())
}

///|
test "a field with the focus no longer shown: the focus not left in it, nothing typed into it, its input method put away (the tree's and an old view's)" {
  for platform in [0, 2] {
    for tree in [true, false] {
      let (ime, words) = field_gone(tree, platform)
      let msg = "tree \{tree}, platform \{platform}"
      assert_false(ime.0, msg="\{msg}: the input method up for what does not show: \{Repr(ime)}")
      assert_eq(words, "a", msg="\{msg}: typed into what does not show: \{words}")
    }
  }
}
