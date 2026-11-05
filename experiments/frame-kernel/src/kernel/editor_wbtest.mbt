// This adapter exercises the actual editor's measurement and rendering under
// the Tester's text host. It is not an Android timing or a full IME migration.
// The field snapshot is committed at the edit's cause, never after measuring it.

///|
test "the existing editor and the independent parent's allocation agree on the first changed frame" {
  let k = Kernel::new(3000)
  defer { k.placement.release() }
  let field = @ui.Field::new(text="a")
  let now = Ref(0.0)
  let picture : Ref[Picture?] = Ref(None)
  let snapshot = fn() -> @ui.FieldLaid {
    { words: field.composed_said(), font_size: 16.0, line: 21.0, text_line: 0.0,
      min_lines: 1, max_lines: 8, trim: false }
  }
  k.commit(0.0, ComposerText(snapshot()))
  let tester = @ui.Tester::new(fn(c) {
    let p = k.frame(now.val, now.val, 300.0, 400.0)
    picture.val = Some(p)
    // The legacy leaf renderer consumes the allocated geometry. It does not
    // measure and send a height back to the independent parent.
    c.column(w=@ui.Px(300.0), h=@ui.Px(400.0), fn() {
      c.box(w=@ui.Px(300.0), h=@ui.Px(p.layout.viewport.height), fn() { }) |> ignore
      c.editor("editor", field~, font_size=16.0, line=21.0, max_lines=8, plain=true, enter_sends=false) |> ignore
    }) |> ignore
  }, w=300.0, h=400.0, time=0.0, platform=0)
  let first = picture.val.unwrap()
  let (_, y, _, h) = tester.get(TextField).rect
  assert_eq((y, h), (first.layout.composer.y, first.layout.composer.height))
  assert_eq(h, 21.0)
  let passes = k.work.layouts
  let measures = k.work.measures
  // A delivered edit: both the existing leaf's model and the independent
  // model receive it before drawing. No dimensions cross this boundary.
  now.val = 100.0
  field.set("a\nb")
  k.commit(100.0, ComposerText(snapshot()))
  tester.frame_at(100.0)
  let after = picture.val.unwrap()
  let (_, y2, _, h2) = tester.get(TextField).rect
  assert_eq((y2, h2), (after.layout.composer.y, after.layout.composer.height))
  assert_eq(h2, 42.0)
  assert_eq(first.layout.viewport.height - after.layout.viewport.height, 21.0)
  assert_eq(k.work.layouts - passes, 1)
  assert_eq(k.work.measures - measures, 1)
  assert_eq(field.text(), "a\nb")
  assert_eq(field.selection(), (3, 3))
}
