// 关于 and 更新日志, one page each in every frame (src/sfdesk about.mbt): at a width of each tier, with a finger and with
// a mouse; laid out as the web's narrow app in a narrow box, as its desktop pages in a wide one.

///|
/// The app over the settings' fixture `w` wide, pointed at as `platform` says (2 a phone's finger, 0 a Mac's mouse;
/// `regular`: a tablet's size classes), the settings' `route` opened under settings.
fn one_page_tester(route : @settings.Route, w : Double, platform? : Int = 0, regular? : Bool = false) -> @ui.Tester raise {
  reset()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h=900.0, platform~)
  if regular {
    let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n")
    assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  }
  t.draw()
  app.nav.push(Settings)
  app.nav.push(Setting(route))
  t.draw()
  t.run_for(@ui.nav_push_ms)
  // laid out Medium, the settings' list in use beside it: the page brought over (as a press on it does) before what is
  // in it is pressed
  if @sfdesk.wide.tape {
    @sfdesk.wide.tape_ask = Some(@sfdesk.TapePane::Page)
    t.draw()
    t.run_for(@sfdesk.side_move_ms)
  }
  t
}

///|
/// `words` pressed where the page shows them: the furthest right of those drawn (the settings' list beside it, left of
/// it, may say the same).
fn tap_in_page(t : @ui.Tester, words : String) -> Unit raise {
  let shown = t.words().filter(fn(w) { w.0 == words && w.5 > 0.5 })
  guard shown.length() > 0 else { fail("no \{words} drawn") }
  let mut at = shown[0]
  for w in shown {
    if w.1 > at.1 {
      at = w
    }
  }
  t.tap(at.1 + at.3 / 2.0, at.2 + at.4 / 2.0)
}

///|
/// Each width and hand the pages are drawn at: a phone with a finger, a narrow window with a mouse, a window between,
/// a tablet with a finger, a desktop's window with a mouse; and whether the page is as wide as the web's narrow app.
let one_page_cases : Array[(Double, Int, Bool, Bool)] = [
  (390.0, 2, false, true),
  (390.0, 0, false, true),
  (720.0, 0, false, false),
  (1100.0, 2, true, false),
  (1280.0, 0, false, false),
]

///|
test "关于, at each width and with either hand: this build, 更新日志, the terms and the privacy policy; a narrow page's rows on cards, a wide one's under its sections' titles" {
  for case in one_page_cases {
    let (w, platform, regular, narrow) = case
    let t = one_page_tester(@settings.Route::About, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("still.fail mbui 0.1") is Some(_), msg=at)
    assert_true(t.find("更新日志") is Some(_), msg=at)
    assert_true(t.find("服务条款") is Some(_), msg=at)
    if narrow {
      // back over the large title, to settings under it; no section's title (the narrow app has none)
      assert_true(t.find("设置") is Some(_), msg=at)
      assert_true(t.find("条款与政策") is None, msg=at)
    } else if w >= 1100.0 {
      assert_true(t.find("条款与政策") is Some(_), msg=at)
    }
    t.tap_text("服务条款")
    assert_true(t.opened().contains("https://still.fail/terms"), msg=at)
    // (the page's row: the settings' list beside a wide one has its own)
    tap_in_page(t, "更新日志")
    t.run_for(@ui.nav_push_ms)
    assert_true(app.nav.top() == Setting(@settings.Route::Changelog), msg=at)
    assert_true(t.find("当前版本 0.1.1300") is Some(_), msg=at)
  }
}

///|
test "关于's version row, at each width and with either hand: its button, 检查更新 or 更新到 the newer build; what is under way under the version, the button turning" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::About, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.query(Button, label="检查更新") is Some(_), msg=at)
    update.available = Some({ "versionCode": 2, "versionName": "0.1.1", "file": "android/stillfail-2.apk" })
    t.draw()
    assert_true(t.query(Button, label="更新到 0.1.1") is Some(_), msg=at)
    // pressed: still.fail cloud asked again before it is downloaded, said under the version; the button turning, its
    // words kept, taking no press
    update.installing = true
    t.draw()
    assert_true(t.find("正在检查最新版本") is Some(_), msg=at)
    assert_true(t.find("更新到 0.1.1") is Some(_), msg=at)
    assert_true(t.query(Button, label="更新到 0.1.1") is None, msg=at)
  }
}

///|
test "关于 on a phone: back goes to settings" {
  let t = one_page_tester(@settings.Route::About, 390.0, platform=2)
  t.tap_text("设置")
  t.run_for(@ui.nav_push_ms)
  assert_true(app.nav.top() == Settings)
}

///|
test "更新日志, at each width and with either hand: the build, a tab a part, each day's changes with their kinds, versions and what is not out yet" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Changelog, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("当前版本 0.1.1300") is Some(_), msg=at)
    assert_true(t.find("此 app") is Some(_), msg=at)
    assert_true(t.find("10 月 19 日") is Some(_), msg=at)
    assert_true(t.find("新增") is Some(_), msg=at)
    assert_true(t.find("0.1.1288") is Some(_), msg=at)
    assert_true(t.find("更新后可用") is Some(_), msg=at)
    // another part: none of its own yet
    // (the tab: the settings' list beside it has a heading of the same name)
    tap_in_page(t, "Station")
    t.draw()
    assert_true(t.find("暂无更新记录") is Some(_), msg=at)
  }
}

///|
test "更新日志 on a phone: a change's kind on a label before its words, which wrap under it; the label one line high" {
  let t = one_page_tester(@settings.Route::Changelog, 390.0, platform=2)
  let words = "对话列表偶尔把同一行显示两次，滑到底再滑回来也不会消失"
  let labels = t.drawn_rects().filter(fn(r) { r.4 == @sf.theme().p.chip && (r.3 - 19.0).abs() < 0.001 })
  assert_true(labels.length() >= 1)
  let rs = t.run_rects(words)
  assert_true(rs.length() >= 2)
  // the words' second line starts where the label does
  assert_true(labels.any(fn(l) { (rs[1].0 - l.0).abs() < 0.001 }))
}
