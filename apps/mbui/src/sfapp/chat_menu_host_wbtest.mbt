// Opening a chat must not add an old-view host just to perform menu choices.

///|
test "a chat pushed from the list adds no old menu host during its slide" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-long", w=351.0, h=805.0, platform=2, wrap=core_lists)
  t.set_frame_period(host_phone_period)
  t.run_for(@ui.move_most_ms * 2.0)
  t.back()
  t.run_for(@ui.move_most_ms * 2.0)
  // The shell still has old views; the chat must add none of its own during or after the transition.
  let shell = t.old_views_hosted()
  let hosted : Array[Int] = []
  t.each_frame(Some(fn() { hosted.push(t.old_views_hosted()) }))
  t.touch_at(0, 138.0, 215.0, t.time())
  t.touch_at(2, 138.0, 215.0, t.time())
  t.run_as_host(@ui.move_most_ms * 2.0)
  t.each_frame(None)
  assert_true(app.nav.top() is Chat(_), msg="the row opened a chat")
  assert_false(hosted.is_empty(), msg="the transition drew frames")
  assert_eq(hosted.filter(fn(n) { n != shell }), [], msg="the chat adds no old menu host: \{hosted}")
}
