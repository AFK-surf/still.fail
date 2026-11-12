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
  new_run()
  let src = over(fixture(mode))
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=900.0, platform~)
  if regular {
    let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n")
    assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  }
  t.draw()
  app.nav.push(Settings)
  // (on the tape opened from the settings' page in use, over it, as their pages open their next: back takes it off)
  if @sfdesk.wide.tape.get() {
    app.nav.push_over(Setting(route))
  } else {
    app.nav.push(Setting(route))
  }
  t.draw()
  t.run_for(@ui.move_most_ms)
  // laid out Medium, the settings' list in use beside it: the page brought over (as a press on it does) before what is
  // in it is pressed
  if @sfdesk.wide.tape.get() {
    @sfdesk.wide.tape_ask.set(Some(@sfdesk.TapePane::Page))
    t.draw()
    t.run_for(@ui.move_most_ms)
  }
  t
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
  assert_eq(app.toast.get().words, "")
  update_reset()
}

///|
test "the update dialog as tall in every stage of a newer build: offered, the person's check, coming (how far unknown, then known), ready, being put in place, failed" {
  let t = one_page_tester(@settings.Route::About, 1280.0)
  let asked : Array[(Result[Json, String]) -> Unit] = []
  update_version.val = 2
  set_update_source(Some({ check: fn(_, now, done) { if now { asked.push(done) } }, url: fn(f) { f } }))
  update.available.set(Some({
    "versionCode": 3,
    "versionName": "0.1.3",
    "file": "mac/stillfail-3.zip",
    "size": 24012345,
    "news": ["修复：一", "修复：二"],
  }))
  t.draw()
  t.post(@hostapi.system_channel, "{\"menu\":\"update.check\"}")
  t.draw()
  t.run_for(@kit.dialog_ms)
  // (the dialog in the window's middle: as tall, its head where it was)
  let head = fn() { t.find("当前版本 0.1.2").unwrap().1 }
  let first = head()
  let same = fn(stage : String) raise {
    t.draw()
    assert_eq(head(), first, msg="\{stage}, as it changed")
    t.run_for(@ui.move_most_ms)
    assert_eq(head(), first, msg="\{stage}")
  }
  t.click(Button, label="下载")
  same("the person's check")
  assert_true(t.find("有新版本 0.1.3") is Some(_))
  assert_true(t.find("正在检查最新版本") is Some(_))
  (asked[0])(Ok(update.available.get().unwrap()))
  t.tells_update("{\"phase\":\"downloading\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-3.zip\"}")
  same("coming, how far unknown")
  t.tells_update("{\"phase\":\"downloading\",\"percent\":13,\"error\":\"\",\"file\":\"stillfail-3.zip\"}")
  same("coming")
  t.tells_update("{\"phase\":\"retrying\",\"percent\":13,\"error\":\"\",\"file\":\"stillfail-3.zip\"}")
  same("coming again")
  t.tells_update("{\"phase\":\"ready\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-3.zip\"}")
  same("ready")
  t.tells_update("{\"phase\":\"installing\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-3.zip\"}")
  same("being put in place")
  t.tells_update("{\"phase\":\"failed\",\"percent\":-1,\"error\":\"incomplete\",\"file\":\"stillfail-3.zip\"}")
  same("failed")
  update_reset()
}

///|
test "关于 on a phone: back goes to settings" {
  let t = one_page_tester(@settings.Route::About, 390.0, platform=2)
  t.tap_text("设置")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Settings)
}

///|
/// Each screen the update dialog opens on: a phone with a finger (a sheet from the foot), a phone's width with a mouse,
/// a desktop's window (a dialog in the window's middle).
let update_screens : Array[(Double, Int)] = [(390.0, 2), (390.0, 0), (1280.0, 0)]

///|
/// 关于 on screen (`w`, `platform`), a newer build known (0.1.3 over this 0.1.2: two lines it brings, its size), what
/// is asked now of still.fail cloud kept in `asked`; the update dialog put up from the menu bar's 检查更新, at rest.
fn update_dialog_tester(w : Double, platform : Int, asked : Array[(Result[Json, String]) -> Unit], newer? : Bool = true) -> @ui.Tester raise {
  @sf.presenters_reset()
  let t = one_page_tester(@settings.Route::About, w, platform~)
  update_version.val = 2
  set_update_source(Some({ check: fn(_, now, done) { if now { asked.push(done) } }, url: fn(f) { f } }))
  if newer {
    update.available.set(Some({
      "versionCode": 3,
      "versionName": "0.1.3",
      "file": "mac/stillfail-3.zip",
      "size": 24012345,
      "news": ["修复：一", "修复：二"],
    }))
  }
  t.draw()
  t.post(@hostapi.system_channel, "{\"menu\":\"update.check\"}")
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(update_dialog_open(), msg="\{w} platform \{platform}: open")
  t
}

///|
/// The update dialog's way out (`label` pressed, its foot's key), gone at rest; the update put back.
fn update_dialog_closed(t : @ui.Tester, label : String, at : String) -> Unit raise {
  t.click(Button, label~)
  t.run_for(@ui.move_most_ms)
  assert_false(update_dialog_open(), msg="\{at}: closed by \{label}")
  assert_false(@sf.presented_drawn(), msg="\{at}: gone")
  update_reset()
}

///|
test "the update dialog as tall in every stage of a newer build on every screen: offered, the person's check, coming, ready, allowed, being put in place, failed" {
  for s in update_screens {
    let (w, platform) = s
    let at = "\{w} platform \{platform}"
    let asked : Array[(Result[Json, String]) -> Unit] = []
    let t = update_dialog_tester(w, platform, asked)
    // (its head where it was: a dialog in the middle as tall, a sheet from the foot as tall; its foot where it was)
    let head = fn() { t.find("当前版本 0.1.2").unwrap().1 }
    let foot = fn() raise { t.get(Button, label="稍后").rect.1 }
    let first = head()
    let first_foot = foot()
    let same = fn(stage : String) raise {
      t.draw()
      assert_eq(head(), first, msg="\{at}: \{stage}, as it changed")
      t.run_for(@ui.move_most_ms)
      assert_eq(head(), first, msg="\{at}: \{stage}")
    }
    assert_true(t.find("有新版本 0.1.3") is Some(_), msg=at)
    assert_true(t.find("修复：二") is Some(_), msg=at)
    t.click(Button, label="下载")
    same("the person's check")
    assert_true(t.find("正在检查最新版本") is Some(_), msg=at)
    (asked[0])(Ok(update.available.get().unwrap()))
    t.tells_update("{\"phase\":\"downloading\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-3.zip\"}")
    same("coming, how far unknown")
    t.tells_update("{\"phase\":\"downloading\",\"percent\":13,\"error\":\"\",\"file\":\"stillfail-3.zip\"}")
    same("coming")
    assert_true(t.find("关闭") is Some(_), msg="\{at}: 关闭 while it comes")
    t.tells_update("{\"phase\":\"retrying\",\"percent\":13,\"error\":\"\",\"file\":\"stillfail-3.zip\"}")
    same("coming again")
    t.tells_update("{\"phase\":\"ready\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-3.zip\"}")
    same("ready")
    assert_true(t.find("重启更新") is Some(_), msg=at)
    t.tells_update("{\"phase\":\"allow\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-3.zip\"}")
    same("allowed")
    assert_true(t.find("允许安装更新") is Some(_), msg=at)
    t.tells_update("{\"phase\":\"installing\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-3.zip\"}")
    same("being put in place")
    t.tells_update("{\"phase\":\"failed\",\"percent\":-1,\"error\":\"incomplete\",\"file\":\"stillfail-3.zip\"}")
    same("failed")
    assert_true(t.find("重试") is Some(_), msg=at)
    assert_eq(foot(), first_foot, msg="\{at}: its foot where it was")
    update_dialog_closed(t, "稍后", at)
  }
}

///|
test "the update dialog asked again while it is open stays the one: no second over it" {
  for s in update_screens {
    let (w, platform) = s
    let at = "\{w} platform \{platform}"
    let asked : Array[(Result[Json, String]) -> Unit] = []
    let t = update_dialog_tester(w, platform, asked)
    let serial = @sf.last_presented()
    // (its title, and 关于's row saying the same under it where it shows)
    let titles = fn() { t.words().filter(fn(w) { w.0 == "有新版本 0.1.3" && w.5 > 0.5 }).length() }
    let was = titles()
    t.post(@hostapi.system_channel, "{\"menu\":\"update.check\"}")
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_eq(@sf.last_presented(), serial, msg="\{at}: none more presented")
    assert_true(update_dialog_open(), msg="\{at}: still open")
    assert_eq(titles(), was, msg="\{at}: no second title")
    update_dialog_closed(t, "稍后", at)
  }
}

///|
test "the update dialog while still.fail cloud is asked: its title, this build under it, a bar to and fro; 取消 closes it; answered none newer, 确定; could not ask, why, 重试 asks again" {
  for s in update_screens {
    let (w, platform) = s
    let at = "\{w} platform \{platform}"
    let asked : Array[(Result[Json, String]) -> Unit] = []
    let t = update_dialog_tester(w, platform, asked, newer=false)
    assert_eq(asked.length(), 1, msg=at)
    guard t.find("正在检查最新版本") is Some((_, title_y)) else { fail("\{at}: no title") }
    guard t.find("当前版本 0.1.2") is Some((_, lead_y)) else { fail("\{at}: no lead") }
    assert_true(title_y < lead_y, msg=at)
    // (from the line under its title to its foot: the bar's room between)
    let asking_gap = t.get(Button, label="取消").rect.1 - lead_y
    update_dialog_closed(t, "取消", at)
    // asked again: none newer
    let asked : Array[(Result[Json, String]) -> Unit] = []
    let t = update_dialog_tester(w, platform, asked, newer=false)
    (asked[0])(Ok(Json::null()))
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("已是最新版本") is Some(_), msg=at)
    // (holding nothing, none of its room: the line under its title straight over its foot)
    guard t.find("当前版本 0.1.2") is Some((_, lead_y)) else { fail("\{at}: no lead") }
    let said_gap = t.get(Button, label="确定").rect.1 - lead_y
    assert_true(said_gap < asking_gap, msg="\{at}: none newer, \{said_gap} under its lead, asking \{asking_gap}")
    update_dialog_closed(t, "确定", at)
    // could not ask: why, in place of this build; 重试 asks again
    let asked : Array[(Result[Json, String]) -> Unit] = []
    let t = update_dialog_tester(w, platform, asked, newer=false)
    (asked[0])(Err("无法获取最新版本：offline"))
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("检查更新失败") is Some(_), msg=at)
    guard t.find("无法获取最新版本：offline") is Some((_, why_y)) else { fail("\{at}: no why") }
    assert_eq(t.get(Button, label="重试").rect.1 - why_y, said_gap, msg="\{at}: could not ask, as none newer")
    t.click(Button, label="重试")
    t.run_for(@ui.move_most_ms)
    assert_eq(asked.length(), 2, msg="\{at}: asked again")
    assert_true(t.find("正在检查最新版本") is Some(_), msg=at)
    update_dialog_closed(t, "取消", at)
  }
}
