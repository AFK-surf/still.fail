// The settings' list (sfpages' settings_list.mbt): one list, the same rows in the same order as a small screen's page
// and as the sidebar beside the settings' pages on a large one.

///|
/// The rows of the settings' list a Tester shows, top to bottom, of `labels`, those left of `edge`.
fn settings_rows_shown(t : @ui.Tester, labels : Array[String], edge : Double) -> Array[String] {
  let seen : Array[(Double, String)] = []
  for w in t.words() {
    if labels.contains(w.0) && w.1 < edge && !seen.iter().any(fn(s) { s.1 == w.0 }) {
      seen.push((w.2, w.0))
    }
  }
  seen.sort_by(fn(a, b) { a.0.compare(b.0) })
  seen.map(fn(s) { s.1 })
}

///|
/// Every row's words in the list's order (the settings' fixture's: 林, 星火工作室) with keyboard and mouse.
// kept across runs: a table, never written
let settings_list_order : Array[String] = [
  "林", "星火工作室", "安全", "密钥", "Station", "连接", "Profile", "自动决策", "记忆", "归档", "用量", "外观", "通知", "快捷键",
  "本机 Station", "本机缓存", "关于",
]

///|
test "the settings' list: the same rows in the same order on a small screen's page and in a large one's sidebar, 下方栏 the small one's alone" {
  // small, with keyboard and mouse (a Mac's narrow window): the gear's page, all of it in a tall window, the bottom
  // bar's row with the bar under it
  let t = @ui.Tester::new(
    {
      let src = fixture_app("settings-home")
      fn(c) { view(c, src) }
    },
    w=390.0,
    h=2400.0,
    platform=0,
  )
  t.run_for(@ui.move_most_ms)
  let small = settings_list_order.copy()
  small.insert(small.search("通知").unwrap() + 1, "下方栏")
  assert_eq(settings_rows_shown(t, small, 390.0), small)
  // large: the sidebar beside the settings' pages, no bottom bar beside them nor a row of it
  let t = wide_tester([], mode="settings", h=1200.0)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  let (edge, _) = t.find("返回会话").unwrap()
  assert_eq(settings_rows_shown(t, small, edge + 200.0), settings_list_order)
}

///|
test "the settings' list: no 下方栏 on a medium screen with a finger, its bar the small screen's alone" {
  new_run()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=720.0, h=1200.0, platform=2)
  t.draw()
  app.nav.push(Settings)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("外观") is Some(_))
  assert_true(t.find("通知") is Some(_))
  assert_true(t.find("下方栏") is None)
}

///|
test "the settings' list: Station, 连接, Profile and 用量 among its rows while the rail has them too" {
  let t = wide_tester([], mode="settings", h=1200.0)
  for place in ["stations", "connects", "profiles", "usage"] {
    assert_true(@sfdesk.rail_items(fixture("settings"), "ws1").contains(place), msg="the rail's: " + place)
  }
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  t.tap_text("连接")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::Connects("")))
  assert_true(@sfdesk.lit_place() == "settings", msg="still in the settings")
}

///|
test "the settings' list: how things stand at each row's end, what is wrong in red" {
  let t = @ui.Tester::new(
    {
      let src = fixture_app("settings-home")
      fn(c) { view(c, src) }
    },
    w=390.0,
    h=2400.0,
    platform=2,
  )
  t.run_for(@ui.move_most_ms)
  // (the settings' fixture: a device waiting in security mode, a secret's use asked, a station off, a connect failing)
  for said in ["1 件待处理", "1 个待批准", "1/2 在线", "1 个出错", "浅色"] {
    assert_true(t.find(said) is Some(_), msg=said)
  }
  // a phone's: its bottom bar, no keys, no station of its own
  assert_true(t.find("下方栏") is Some(_))
  assert_true(t.find("快捷键") is None)
  assert_true(t.find("本机 Station") is None)
  // what has a page of its own elsewhere: not a row of its own
  assert_true(t.find("更新日志") is None)
  assert_true(t.find("权限") is None)
}
