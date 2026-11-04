///|
test "a retained field changes its line limit and Enter policy without replacing the editor or selection" {
  let t = Tester::new(fn(_) {  }, w=300.0, h=240.0)
  let f = Field::new(text="one\ntwo\nthree")
  let lines = @signals.signal(1)
  let line = @signals.signal(20.0)
  let sends = @signals.signal(false)
  let limit = @signals.signal(0)
  let made = Ref(0)
  let held : Ref[@view.View?] = Ref(None)
  let given : Array[String] = []
  set_view_app(fn(root) {
    made.val += 1
    held.val = Some(field(
      root,
      f,
      font_size=12.0,
      max_lines_by=fn() { lines.get() },
      line_by=fn() { line.get() },
      enter_by=fn() { sends.get() },
      paste_limit_by=fn() { limit.get() },
      submitted=fn(words) { given.push(words) },
    ))
  })
  t.draw()
  let id = held.val.unwrap().id()
  let short = held.val.unwrap().rect().3
  f.pick(4, 7)
  lines.set(4)
  line.set(25.0)
  sends.set(true)
  limit.set(64)
  t.draw()
  assert_eq((made.val, held.val.unwrap().id(), f.selection()), (1, id, (4, 7)))
  assert_true(held.val.unwrap().rect().3 > short)
  assert_eq((f.st.enter_sends, f.st.limit), (true, 64))
  f.focus()
  t.draw()
  t.enter()
  assert_eq(given, ["one\ntwo\nthree"])
  assert_eq(f.text(), "one\ntwo\nthree")
}
