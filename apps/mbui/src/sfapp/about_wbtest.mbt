// The settings' pages in the whole app, at a width of each tier, with a finger and with a mouse (one_page_tester): what
// the shell does around a page (its frame's back, the menu bar's 检查更新). What a page alone does is its own tests'
// beside it (src/sfpages: about_wbtest.mbt, …).
///|
/// The app over the settings' fixture `w` wide, pointed at as `platform` says (2 a phone's finger, 0 a Mac's mouse;
/// `regular`: a tablet's size classes), the settings' `route` opened under settings; `mode`: the fixture's (a settings
/// one), as `over` has it.
fn one_page_tester(
  route : @settings.Route,
  w : Double,
  platform? : Int = 0,
  regular? : Bool = false,
  mode? : String = "settings",
  over? : (Source) -> Source = fn(s) { s },
) -> @ui.Tester raise {
  reset()
  let src = over(fixture(mode))
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=900.0, platform~)
  if regular {
    let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n")
    assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  }
  t.draw()
  app.nav.push(Settings)
  // (on the tape opened from the settings' page in use, over it, as their pages open their next: back takes it off)
  if @sfdesk.wide.tape {
    app.nav.push_over(Setting(route))
  } else {
    app.nav.push(Setting(route))
  }
  t.draw()
  t.run_for(@ui.move_most_ms)
  // laid out Medium, the settings' list in use beside it: the page brought over (as a press on it does) before what is
  // in it is pressed
  if @sfdesk.wide.tape {
    @sfdesk.wide.tape_ask.set(Some(@sfdesk.TapePane::Page))
    t.draw()
    t.run_for(@ui.move_most_ms)
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
test "the update dialog with a newer build: what it brings (its first five, 还有 n 项); 下载 asks still.fail cloud now, then hands the newest to the host, how it comes under them, 关闭 beside it; ready, 重启更新 asks again, then puts it in place" {
  let t = one_page_tester(@settings.Route::About, 1280.0)
  let asked : Array[(Result[Json, String]) -> Unit] = []
  update_version.val = 2
  set_update_source(Some({ check: fn(_, now, done) { if now { asked.push(done) } }, url: fn(f) { f } }))
  update.available.set(Some({
    "versionCode": 3,
    "versionName": "0.1.3",
    "file": "mac/stillfail-3.zip",
    "news": ["修复：一", "修复：二", "修复：三", "改进：四", "改进：五", "新增：六", "新增：七"],
  }))
  t.draw()
  t.post(@hostapi.system_channel, "{\"menu\":\"update.check\"}")
  t.draw()
  t.run_for(@kit.dialog_ms)
  // known already: offered, not asked again
  assert_eq(asked.length(), 0)
  assert_true(t.find("有新版本 0.1.3") is Some(_))
  assert_true(t.find("改进：五") is Some(_))
  assert_true(t.find("新增：六") is None)
  assert_true(t.find("还有 2 项") is Some(_))
  assert_true(t.find("稍后") is Some(_))
  t.click(Button, label="下载")
  t.draw()
  // still.fail cloud asked now first (the newest there is), checking said meanwhile; then handed to the host, on any
  // network (the person's word)
  assert_eq(asked.length(), 1)
  assert_true(t.find("正在检查最新版本") is Some(_))
  (asked[0])(Ok(update.available.get().unwrap()))
  t.draw()
  assert_eq(t.update_asked(), ["fetch stillfail-3.zip false", "fetch stillfail-3.zip true"])
  t.tells_update("{\"phase\":\"downloading\",\"percent\":40,\"error\":\"\",\"file\":\"stillfail-3.zip\"}")
  t.draw()
  assert_true(t.find("正在下载 0.1.3 · 40%") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("关闭") is Some(_))
  // ready: 重启更新, which puts it in place
  t.tells_update("{\"phase\":\"ready\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-3.zip\"}")
  t.draw()
  t.click(Button, label="重启更新")
  t.draw()
  assert_eq(asked.length(), 2)
  (asked[1])(Ok(update.available.get().unwrap()))
  t.draw()
  assert_eq(t.update_asked(), [
    "fetch stillfail-3.zip false", "fetch stillfail-3.zip true", "fetch stillfail-3.zip false", "apply",
  ])
  assert_eq(app.toast.get(), "")
  update_reset()
}

///|
test "关于 on a phone: back goes to settings" {
  let t = one_page_tester(@settings.Route::About, 390.0, platform=2)
  t.tap_text("设置")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Settings)
}
