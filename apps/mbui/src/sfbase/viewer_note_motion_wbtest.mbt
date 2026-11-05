///|
test "a note card reads the clock only during its entrance, and releases its field when done" {
  reset()
  @sf.set_words(fill)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=1280.0, h=844.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.show(fn() { marks_said(); marking.note >= 0 }, note_box_node)
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  assert_false(tree.clock_read())
  marks_open_note(t.ctx(), 1)
  let at = t.time()
  t.frame_at(at + note_pop_ms / 2.0)
  let cards = fn() { tree.drawn().filter(fn(d) { d.ground == note_ground }) }
  assert_eq(cards().length(), 1)
  assert_true(cards()[0].alpha > 0.0 && cards()[0].alpha < 1.0)
  assert_true(tree.clock_read(), msg="coming in: the card follows its time")
  t.frame_at(at + note_pop_ms)
  assert_eq(cards().map(fn(d) { d.alpha }), [1.0])
  assert_false(tree.clock_read(), msg="come in: the card stops following time at its declared end")
  marks_note_done(t.ctx())
  t.draw()
  assert_eq(cards().length(), 0)
  assert_eq(t.all(TextField, label=pv("android-chat.annotate.write")).length(), 0)
  assert_false(tree.clock_read(), msg="done: no clock reader left")
}
