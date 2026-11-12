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
test "记忆, 关于, 更新日志, 一台 station 的记忆, 归档, 一台 station 的归档 and 自动决策 as places of the bottom bar, made once: the top bar names each and has settings, what it holds under it; the window wider, the same place still shows" {
  // (each place's words read in its own run, once it has begun: read before, they are the run before's)
  let cases : Array[(String, () -> String)] = [
    ("memories", fn() { "全局记忆 · 项目记忆" }),
    ("about", fn() { "服务条款" }),
    ("changelog", fn() { "10 月 19 日" }),
    ("memory:ws1/st1", fn() { "发布流程" }),
    ("archiving", fn() { "Willow" }),
    ("archiving:ws1/st1", fn() { "按模型判断" }),
    ("decisions-settings", fn() { @sf.t("web-pages.automaticDecisions.completion") }),
  ]
  for case in cases {
    let (place, said) = case
    new_run()
    let src = fixture("settings")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=900.0, platform=2)
    let words = said()
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

///|
test "一台 station 的记忆 as a place, become another station's in its place, on each screen: that station's memory asked for, its name and rows the tree's" {
  for w in [390.0, 700.0, 1280.0] {
    new_run()
    let asked : Array[String] = []
    let src = topic_asked(fixture("settings"), "memory", "station", asked)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=900.0, platform=2)
    t.draw()
    app.nav.replace(Place("memory:ws1/st1"))
    t.draw()
    t.run_for(@ui.move_most_ms)
    let first = (asked.last(), tree_words_drawn().iter().any(fn(o) { o.contains("发布流程") }))
    app.nav.become(Place("memory:ws1/st2"))
    t.run_for(@ui.move_most_ms)
    let own = tree_words_drawn()
    assert_eq(
      (first, asked.last(), own.iter().any(fn(o) { o.contains("发布流程") })),
      ((Some("ws1/st1"), true), Some("ws1/st2"), true),
      msg="at \{w}: \{Repr(own)}",
    )
  }
}

///|
test "一台 station 的记忆 as a place over another place, on the tape and wide: no back over it, in the page nor in the tape's bar (a place of the rail's has none, whatever is under it)" {
  for w in [700.0, 1280.0] {
    new_run()
    let src = fixture("settings")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=900.0, platform=0)
    t.draw()
    let back = @sfbase.back_label(Place("memories"))
    let backs = fn() { t.semantics().filter(fn(s) { s.label == back && !s.hidden }).length() }
    app.nav.replace(Place("memories"))
    t.run_for(@ui.move_most_ms)
    @sfdesk.bring_page()
    t.run_for(@ui.move_most_ms)
    let alone = backs()
    app.nav.push(Place("memory:ws1/st1"))
    t.run_for(@ui.move_most_ms)
    // (on the tape, its panel the one in use: what its bar says read out)
    @sfdesk.bring_page()
    t.run_for(@ui.move_most_ms)
    assert_true(tree_words_drawn().iter().any(fn(o) { o.contains("发布流程") }), msg="at \{w}: \{Repr(tree_words_drawn())}")
    assert_eq(backs(), alone, msg="a back over it at \{w}")
  }
}

///|
test "关于 as a place of the bottom bar become 版本 in its place (another of its names): the same page, its top bar named anew" {
  new_run()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=900.0, platform=2)
  t.draw()
  app.nav.replace(Place("about"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(place_label("about")) is Some(_), msg="named 关于's")
  app.nav.replace(Place("version"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("服务条款") is Some(_), msg="the same page")
  if place_label("version") != place_label("about") {
    assert_true(t.find(place_label("version")) is Some(_), msg="named anew: \{t.drawn_text()}")
    assert_true(t.find(place_label("about")) is None, msg="the old name gone")
  }
}
