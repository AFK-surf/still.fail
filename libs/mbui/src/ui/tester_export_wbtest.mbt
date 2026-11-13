///|
test "a frame said a line for each thing it drew, who drew it and its words" {
  let t = Tester::new(fn(c) {
    c.box(w=Px(200.0), h=Px(100.0), bg=0x3366CCFFL, radius=8.0, fn() { c.text("hello", size=12.0) |> ignore })
    |> ignore
  }, w=400.0, h=300.0)
  t.export_frames()
  t.draw()
  let lines = t.frame_export()
  assert_true(lines.iter().any(fn(l) { l.has_prefix("rect 0 0 200 100 #3366cc a=ff r=8,8,8,8") }), msg="\{Repr(lines)}")
  assert_true(lines.iter().any(fn(l) { l.has_prefix("glyphs ") && l.has_suffix("\"hello\"") }), msg="\{Repr(lines)}")
}

///|
test "a point probed: what a press there comes to, the pointer's shape, what lights up" {
  let t = Tester::new(fn(c) {
    c.button("go") |> ignore
  }, w=400.0, h=300.0)
  t.export_frames()
  t.draw()
  let said = t.probe_at(20.0, 20.0)
  assert_true(said.has_prefix("target="), msg=said)
  assert_true(t.focus_said() != "", msg=t.focus_said())
}
