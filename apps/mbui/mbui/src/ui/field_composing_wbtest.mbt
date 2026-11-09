// The draft can wait for an input method to finish without inferring its state from the text it displays.

///|
test "a field tells composition start, commit, cancellation and app writes with its text as one change" {
  let f = Field::new()
  let t = Tester::new(fn(_) {  }, w=300.0, h=100.0, platform=0)
  set_view_app(fn(root) { field(root, f) |> ignore })
  t.draw()
  f.focus()
  let seen : Array[(Bool, String, String)] = []
  let stop = @signals.effect(fn() { seen.push((f.composing(), f.text(), f.composed_said())) })
  on_text(1, "中", 1, 0)
  on_text(2, "", 0, 0)
  assert_eq(seen, [(false, "", ""), (true, "", "中"), (false, "中", "中")], msg="commit: the same displayed words still end composing")
  on_text(1, "x", 1, 0)
  on_text(1, "", 0, 0)
  assert_eq(seen.last(), Some((false, "中", "中")), msg="cancel: composing ends without a committed edit")
  on_text(1, "y", 1, 0)
  f.set("server")
  assert_eq(seen.last(), Some((false, "server", "server")), msg="set: the text and composition change together")
  on_text(1, "z", 1, 0)
  let before = seen.length()
  assert_eq(f.take(), "serverz")
  assert_eq(seen.length(), before + 1)
  assert_eq(seen.last(), Some((false, "", "")), msg="take: the committed text and its removal are one change")
  stop()
}

///|
test "an Android composing region tells when its state is applied and when it is committed" {
  let field = Field::new(text="a")
  let t = Tester::new(fn(c) { c.editor("field", field~) |> ignore }, w=300.0, h=100.0, platform=2)
  t.tap(20.0, 20.0)
  let seen : Array[(Bool, String, String)] = []
  let stop = @signals.effect(fn() { seen.push((field.composing(), field.text(), field.composed_said())) })
  t.ime_state("a你", 2, 2, ca=1, cb=2)
  t.ime_state("a你", 2, 2)
  assert_eq(seen, [(false, "a", "a"), (true, "a", "a你"), (false, "a你", "a你")])
  stop()
}
