// A new profile's models, a secret's page, a place's first on the desktop,
// over the whole app and the settings' fixture (a profile's own page: src/sfpages accounts_wbtest.mbt).

///|
/// The desk's page wheeled down until `words` shows on it (above the window's foot).
fn desk_shown(t : @ui.Tester, words : String) -> Unit {
  t.move(800.0, 400.0)
  for _ in 0..<12 {
    match t.find(words) {
      Some((_, y)) if y < 760.0 => break
      _ => t.wheel(800.0, 400.0, 300.0)
    }
  }
}

///|
test "wide: a new profile's models chosen on a page of their own, then on to its page" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings")
  t.draw()
  app.nav.push(Setting(@settings.Route::PickModels("ws1/st1", "cc")))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("Opus 5.5") is Some(_) && t.find("Haiku 5") is Some(_), msg="its whole list to tick")
  match t.find("完成") {
    Some((x, y)) => t.tap(x, y)
    None => abort("no 完成")
  }
  t.run_for(@ui.nav_push_ms)
  assert_true(app.nav.top() is Setting(@settings.Route::Profile("ws1/st1", "cc")), msg="on to its page")
}

///|
test "wide: a secret's page says what it is, how agents may get it and when they did, its content masked until opened" {
  let t = wide_tester([], mode="settings")
  t.draw()
  app.nav.push(Setting(@settings.Route::VaultItem("v1", "it1")))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("GitHub token") is Some(_))
  // the core's words of it
  assert_true(t.find("代理 · 限 api.github.com") is Some(_), msg="how it is given")
  assert_true(t.find("跟随默认 · 直到对话归档") is Some(_), msg="its longest grant")
  assert_true(t.find("git push origin main · 代理") is Some(_), msg="a use, how")
  // not opened: its field's name over dots
  assert_true(t.find("值") is Some(_))
  assert_true(t.find("ghp_") is None, msg="nothing of it shown")
}

///|
test "wide: the Station place with none in the workspace is the first to add, not a phone's page" {
  let t = wide_tester([], mode="settings-first-station")
  t.draw()
  app.nav.replace(Place("stations"))
  t.run_for(@ui.nav_push_ms)
  // its scene and its one thing to do (the sidebar's 添加 station too)
  assert_true(t.find_last("添加 station") is Some(_))
}
