///|
test "a retained editor is found by its changing hint as an old editor is, even with a draft in it" {
  let t = Tester::new(fn(_) {  }, w=300.0, h=200.0)
  let hint = @signals.signal("Write a message")
  let f = Field::new()
  let visible = @signals.signal(true)
  set_view_app(fn(root) {
    root.show(at_once=true, fn() { visible.get() }, fn(p) {
      field(p, f, placeholder_by=fn() { hint.get() }) |> ignore
    })
  })
  t.draw()
  let at = t.find("message").unwrap()
  assert_eq(t.find_last("message"), Some(at))
  assert_true(t.rect_of("message") is Some(_))
  assert_eq(t.words().filter(fn(w) { w.0 == "Write a message" }).length(), 1)
  t.tap(at.0, at.1)
  t.type_text("a draft")
  assert_true(t.get(TextField, label="Write a message").focused)
  assert_true(t.find("message") is Some(_))
  hint.set("Another hint")
  t.draw()
  assert_true(t.find("message") is None)
  assert_true(t.find("Another hint") is Some(_))
  visible.set(false)
  t.draw()
  assert_true(t.find("Another hint") is None)
}
