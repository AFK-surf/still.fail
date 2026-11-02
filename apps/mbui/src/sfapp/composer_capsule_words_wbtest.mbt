// The composer's capsule (its field without the focus, nothing in it) on a Mac, the system's words larger (1.3, 2): its
// round buttons as far in over and under as at their ends, concentric with it (the corner rule, held on every frame at
// rest), its text's room as high as they are, its line in its middle (text_shut). Main's (acb0068613) let a taller
// line push its buttons in over and under; in a file of its own, as a fault of it ends its program.

///|
test "a chat 700 wide on a Mac, its composer let go of (its capsule), the system's words 1.3, 2 and 1 again: the capsule's round buttons concentric with it each time" {
  new_run()
  let src = fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=700.0, h=844.0, platform=0, window_corner=16.0)
  t.set_window_inset(true)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.ctx().blur()
  t.draw()
  t.run_for(@sfpages.let_go_ms + @ui.move_most_ms + @sf.hint_back_ms)
  let field = fn() { t.semantics().filter(fn(s) { s.role == @ui.Role::TextField }).map(fn(s) { (s.label, s.rect) }) }
  assert_true(t.ctx().focused_id() == 0 && t.find("按空格输入") is Some(_), msg="its capsule, let go of: \{field()}")
  // (the system's words larger, much larger (its line then taller than the round buttons), as they were: the corner
  // rule held on each, its capsule still)
  for scale in [1.3, 2.0, 1.0] {
    t.set_font_scale(scale)
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("按空格输入") is Some(_), msg="words \{scale}: its capsule still: \{field()}")
  }
}
