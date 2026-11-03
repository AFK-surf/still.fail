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

///|
test "记忆, 关于 and 更新日志 as places of the bottom bar, made once: the top bar names each and has settings, what it holds under it; the window wider, the same place still shows" {
  for case in [("memories", "全局记忆 · 项目记忆"), ("about", "服务条款"), ("changelog", "10 月 19 日")] {
    let (place, words) = case
    new_run()
    let src = fixture("settings")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=900.0, platform=2)
    t.draw()
    app.nav.replace(Place(place))
    t.draw()
    t.run_for(@ui.move_most_ms)
    guard t.rect_of(words) is Some((_, y, _, _)) else { fail("\{place}: \{words} not shown") }
    // (the top bar: the place's name and settings, what the page holds under it)
    let label = place_label(place)
    guard t.words().search_by(fn(w) { w.0 == label && w.5 > 0.5 }) is Some(i) else { fail("\{place}: no top bar's name") }
    let name_y = t.words()[i].2
    assert_true(name_y < y, msg="\{place}: the bar over what it holds: \{name_y} \{y}")
    let settings = t.get(Button, label=tr("android-chat.home.settings"))
    assert_true(settings.rect.1 < y, msg="\{place}: settings in the bar")
    // (no large title of its own under the bar's)
    assert_false(t.words().any(fn(w) { w.0 == label && w.4 > 30.0 && w.5 > 0.5 }), msg="\{place}: \{t.drawn_text()}")
    // (wider: on the tape, then beside the sidebar, the place shown still)
    for w in [600.0, 1280.0] {
      t.resize(w, 900.0)
      t.run_for(@ui.move_most_ms)
      assert_true(app.nav.top() == Place(place), msg="\{place} at \{w}")
      assert_true(t.find(words) is Some(_), msg="\{place} at \{w}: \{t.drawn_text()}")
    }
  }
}
