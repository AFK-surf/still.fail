///|
test "putting a reference into a retained field keeps the core's marks when its answer is synchronous" {
  reset()
  let t = @ui.Tester::new(fn(_) {  })
  let field = @ui.Field::new(text="https://example.invalid/chat")
  let src = made_source(call=fn(name, _, done) {
    if name == "ref.marks" { done(Ok({ "marks": [{ "start": 0, "end": 5 }] })) }
    else { done(Ok({})) }
  })
  @ui.set_view_app(fn(root) {
    let editor = @ui.field(root, field)
    editor.reacts(fn() { field.text() }, fn(_) {
      refs_edits_now(src, "draft", field, "workspace/station", false)
    })
  })
  t.draw()
  refs_put("draft", field, "@[首页] 后文")
  assert_eq(field.text(), "@[首页] 后文")
  assert_eq(refs_marked("draft"), Some(true))
  assert_eq(refs_sent_marks("draft", field.text()), [(0, 5)])
  field.set("")
  assert_eq(refs_marked("draft"), Some(false))
}

///|
test "a mark in the field: as many code units as its words, its `[` and `]` no room, its `@` and title as words_runs inks them" {
  reset()
  let t = @ui.Tester::new(fn(_) {  })
  let field = @ui.Field::new()
  let src = made_source(call=fn(name, _, done) {
    if name == "ref.marks" { done(Ok({ "marks": [{ "start": 0, "end": 5 }] })) }
    else { done(Ok({})) }
  })
  @ui.set_view_app(fn(root) {
    let editor = @ui.field(root, field)
    editor.reacts(fn() { field.text() }, fn(_) {
      refs_edits_now(src, "draft", field, "workspace/station", false)
    })
  })
  t.draw()
  refs_put("draft", field, "@[首页] 后文")
  let accent = 0x112233FFL
  let (shown, spans) = (refs_look("draft", accent))(field.text())
  assert_eq(shown, "\u{200B}@首页\u{200B} 后文")
  assert_eq(spans, [(1, 2, @sf.alpha(accent, ref_at_alpha)), (2, 4, accent)])
}
