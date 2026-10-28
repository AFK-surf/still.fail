// Words dragged in from another app (a browser page's text) and let go on the window (drop.mbt's "words"): on a field,
// in where they were let go, as a paste's; beside one, only on a box that takes them for its field (Ctx::words_into),
// the frame they came. Words 10 high, Latin 5 across (editor_keys_test.mbt's keys_field; editor_pointer_test.mbt's
// letter_at).

///|
test "words let go on a field go in where they were let go, a step of their own to undo, the field taking the focus" {
  let other = @ui.Field::new(text="other")
  let f = @ui.Field::new(text="hello world")
  let t = @ui.Tester::new(
    fn(c) {
      c.column(w=Fill(1.0), fn() {
        c.editor("a", field=other, placeholder="first field", font_size=10.0, plain=true, enter_sends=false) |> ignore
        c.text("between") |> ignore
        c.editor("b", field=f, placeholder="second field", font_size=10.0, plain=true, enter_sends=false) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=200.0,
  )
  t.draw()
  // where the second field's words start (its caret at its start)
  let (bx, by, _, bh) = t.rect_of("second field").unwrap()
  t.tap(bx + 2.0, by + bh / 2.0)
  f.set("hello world", caret=0)
  t.draw()
  let (x0, y0, _, h) = t.ime_rect()
  // the other field has the focus as they come
  let (ax, ay, _, ah) = t.rect_of("first field").unwrap()
  t.tap(ax + 2.0, ay + ah / 2.0)
  assert_eq(t.ime().1, "other")
  let (x, y) = letter_at(x0, y0, h, 6)
  t.drop_words(x, y, "brave ")
  t.frame()
  assert_eq(f.text(), "hello brave world")
  assert_eq(f.selection(), (12, 12))
  assert_eq(other.text(), "other")
  // the field they went into has the focus: what is typed goes on there
  assert_eq(t.ime().1, "hello brave world")
  t.type_text("big ")
  assert_eq(f.text(), "hello brave big world")
  // undone: what was typed, then the words let go in
  t.key(@ui.key_of_char('z'), mods=@ui.mod_cmd)
  assert_eq(f.text(), "hello brave world")
  t.key(@ui.key_of_char('z'), mods=@ui.mod_cmd)
  assert_eq(f.text(), "hello world")
}

///|
test "words let go beside a field go into it only on a box that takes them for it, at its caret, the frame they came" {
  let f = @ui.Field::new(text="ab")
  let takes = Ref(true)
  let t = @ui.Tester::new(
    fn(c) {
      c.column(w=Fill(1.0), fn() {
        // a box pressed for its field (a composer's capsule): words let go on it beside the field are the field's
        let cap = c.id("cap")
        c.clicked(cap) |> ignore
        if takes.val {
          c.words_into(cap, "e")
        }
        c.box(id=cap, w=Fill(1.0), pad=40.0, fn() {
          c.editor("e", field=f, placeholder="the field", font_size=10.0, plain=true, enter_sends=false) |> ignore
        })
        |> ignore
        c.text("beside it") |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
  t.draw()
  let (ex, ey, _, _) = t.rect_of("the field").unwrap()
  // on the box, well over its field: at the field's caret (its end), the field focused
  t.drop_words(ex + 50.0, ey - 36.0, "cd")
  t.frame()
  assert_eq(f.text(), "abcd")
  assert_eq(f.selection(), (4, 4))
  assert_eq(t.ime().1, "abcd")
  // beside the box: nothing takes them
  let (bx, by) = t.find("beside it").unwrap()
  t.drop_words(bx, by, "ef")
  t.frame()
  t.frame()
  assert_eq(f.text(), "abcd")
  // let go on the box in a frame whose build takes none: not taken by a later one
  takes.val = false
  t.drop_words(ex + 50.0, ey - 36.0, "gh")
  t.frame()
  takes.val = true
  // (built again: a press beside it)
  t.tap(bx, by)
  t.frame()
  assert_eq(f.text(), "abcd")
}

///|
test "words dropped on a modal or its ground do not reach the page underneath" {
  let field = @ui.Field::new(text="draft")
  let t = @ui.Tester::new(fn(c) {
    let page = c.id("page")
    c.words_into(page, "composer")
    c.box(id=page, w=Fill(1.0), h=Fill(1.0), taps=false, points=true, fn() {
      c.editor("composer", field~, placeholder="composer") |> ignore
    }) |> ignore
    c.overlay("modal", modal=true, fn() {
      c.box(id=c.id("panel"), tx=20.0, ty=20.0, w=Px(150.0), h=Px(100.0), fn() {
        c.text("dialog") |> ignore
      }) |> ignore
    }) |> ignore
  }, w=300.0, h=300.0)
  t.draw()
  t.drop_words(50.0, 50.0, "on the dialog")
  t.frame()
  assert_eq(field.text(), "draft")
  t.drop_words(250.0, 250.0, "on the ground")
  t.frame()
  assert_eq(field.text(), "draft")
}

///|
test "a popover blocks words dropped on it and leaves the page outside it reachable" {
  let field = @ui.Field::new(text="draft")
  let t = @ui.Tester::new(fn(c) {
    let page = c.id("page")
    c.words_into(page, "composer")
    c.box(id=page, w=Fill(1.0), h=Fill(1.0), taps=false, points=true, fn() {
      c.editor("composer", field~, placeholder="composer") |> ignore
    }) |> ignore
    c.overlay("popover", fn() {
      c.box(id=c.id("panel"), tx=20.0, ty=20.0, w=Px(150.0), h=Px(100.0), fn() {
        c.text("menu") |> ignore
      }) |> ignore
    }) |> ignore
  }, w=300.0, h=300.0)
  t.draw()
  t.drop_words(50.0, 50.0, "on the menu")
  t.frame()
  assert_eq(field.text(), "draft")
  t.drop_words(250.0, 250.0, " outside")
  t.frame()
  assert_eq(field.text(), "draft outside")
}

///|
test "words dropped beside a field in a dialog belong to that field, not the page underneath" {
  let page_field = @ui.Field::new(text="draft")
  let dialog_field = @ui.Field::new(text="dialog")
  let t = @ui.Tester::new(fn(c) {
    let page = c.id("page")
    c.words_into(page, "composer")
    c.box(id=page, w=Fill(1.0), h=Fill(1.0), taps=false, points=true, fn() {
      c.editor("composer", field=page_field, placeholder="composer") |> ignore
    }) |> ignore
    c.overlay("modal", modal=true, fn() {
      let panel = c.id("panel")
      c.words_into(panel, "dialog-field")
      c.box(id=panel, tx=20.0, ty=20.0, w=Px(200.0), h=Px(180.0), pad=40.0, fn() {
        c.editor("dialog-field", field=dialog_field, placeholder="dialog field") |> ignore
      }) |> ignore
    }) |> ignore
  }, w=300.0, h=300.0)
  t.draw()
  t.drop_words(50.0, 150.0, " words")
  t.frame()
  assert_eq(page_field.text(), "draft")
  assert_eq(dialog_field.text(), "dialog words")
  assert_eq(t.ime().1, "dialog words")
}
