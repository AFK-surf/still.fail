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
