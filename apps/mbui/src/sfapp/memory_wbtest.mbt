// 记忆 as a place of the bottom bar (the page itself: src/sfpages memory_wbtest.mbt): the top bar names it.

///|
test "记忆 as a place of the bottom bar: the top bar names it, no title of its own" {
  new_run()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=900.0, platform=2)
  t.draw()
  app.nav.replace(Place("memories"))
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("全局记忆 · 项目记忆") is Some(_))
  // no large title of its own under the top bar's
  assert_false(t.words().any(fn(w) { w.0 == "记忆" && w.4 > 30.0 && w.5 > 0.5 }), msg=t.drawn_text())
}
