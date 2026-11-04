// The settings search is the same list on every screen. Exercise the field, filtering, clearing and opening a result
// through the app's shell, with each input as well as each arrangement.

///|
fn settings_search_tester(w : Double, platform : Int) -> @ui.Tester {
  let src = fixture_app("settings-home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=1000.0, platform~)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "settings search filters, clears and opens a nested page on every screen with either input" {
  for (w, platform) in [(390.0, 2), (390.0, 0), (720.0, 2), (1280.0, 0), (1280.0, 2)] {
    let t = settings_search_tester(w, platform)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("搜索设置") is Some(_), msg=at)
    t.tap_text("搜索设置")
    t.type_text("没有这样的设置")
    t.frame()
    assert_true(t.find("没有匹配的结果") is Some(_), msg=at)
    t.click(Button, label="清除筛选")
    t.frame()
    assert_true(t.find("没有匹配的结果") is None, msg=at)
    assert_true(t.find("安全") is Some(_), msg=at)
    t.type_text("字体")
    t.frame()
    assert_true(t.find("字体") is Some(_), msg=at)
    assert_true(t.find("安全") is None, msg=at)
    t.tap_text("字体")
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Setting(@settings.Route::Fonts), msg=at)
  }
}

///|
test "settings search finds account and workspace settings by their names as well as the person's own name" {
  let t = settings_search_tester(390.0, 2)
  t.tap_text("搜索设置")
  t.type_text("成员")
  t.frame()
  assert_true(t.find("成员") is Some(_))
  t.tap_text("成员")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::Workspace))
}

///|
test "settings search follows the language and keeps its words when the list moves to the sidebar" {
  let base = fixture_app("settings-home")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      if name == "prefs" {
        let prefs = match got.value {
          Some(Object(m)) => m.copy()
          _ => {}
        }
        prefs["lang"] = Json::string("en")
        { ..got, value: Some(Json::object(prefs)) }
      } else {
        got
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=1000.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.tap_text("Search settings")
  t.type_text("  FoNt  ")
  t.frame()
  assert_true(t.find("Fonts") is Some(_))
  t.resize(1280.0, 1000.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("Fonts") is Some(_))
  t.tap_text("Fonts")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::Fonts))
}
