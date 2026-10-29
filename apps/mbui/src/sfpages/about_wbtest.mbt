// 关于 and 更新日志 (about.mbt) alone, at each width, with a finger and with a mouse: laid out as the web's narrow app in
// a narrow box, as its desktop pages in a wide one; the update dialog the page opens over it.

///|
test "关于, at each width and with either hand: this build, 更新日志, the terms and the privacy policy; a narrow page's rows on cards, a wide one's under its sections' titles" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(About, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("still.fail mbui 0.1") is Some(_), msg=at)
    assert_true(t.find("更新日志") is Some(_), msg=at)
    assert_true(t.find("服务条款") is Some(_), msg=at)
    // its sections' titles laid out wide alone (the narrow app has none)
    assert_eq(t.find("条款与政策") is Some(_), laid_wide(w), msg=at)
    t.tap_text("服务条款")
    assert_true(t.opened().contains("https://still.fail/terms"), msg=at)
    t.tap_text("更新日志")
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Setting(Changelog), msg=at)
    assert_true(t.find("当前版本 0.1.1300") is Some(_), msg=at)
  }
}

///|
test "关于's version rows, at each width and with either hand: this build alone on its row; under it a row doing what it says, 检查更新 or 更新到 the newer build, what is under way under its words and the bar under them, the row as tall all the way, pressed still" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(About, w, platform~)
    @sffixture.fixture_updates()
    t.draw()
    let at = "\{w} platform \{platform}"
    assert_true(t.query(Link, label="检查更新") is Some(_), msg=at)
    @sfbase.update.available.set(Some({ "versionCode": 2, "versionName": "0.1.1", "file": "android/stillfail-2.apk" }))
    t.draw()
    assert_true(t.query(Link, label="更新到 0.1.1") is Some(_), msg=at)
    // pressed: still.fail cloud asked again before it is downloaded, said under the row's words, its words kept; the
    // row pressed again opens the dialog saying how it goes
    @sfbase.update.installing.set(true)
    t.draw()
    assert_true(t.find("正在检查最新版本") is Some(_), msg=at)
    assert_true(t.query(Link, label="更新到 0.1.1") is Some(_), msg=at)
    // nothing beside what is under way, nor beside the build's name: each whole on its line
    let (_, ny, _, nh) = t.rect_of("正在检查最新版本").unwrap()
    let (_, uy, _, uh) = t.rect_of("更新到 0.1.1").unwrap()
    assert_true(ny >= uy + uh, msg=at)
    assert_true(t.beside_faults().length() == 0, msg="\{at}: \{t.beside_faults()}")
    // asked again, downloading, installing: the row as tall each way (what is under it where it was)
    let (_, under, _, _) = t.rect_of("更新日志").unwrap()
    @sfbase.update.installing.set(false)
    for told in [("downloading", 40, "下载中 40%"), ("downloading", -1, "下载中"), ("installing", -1, "正在安装")] {
      t.tells_update("{\"phase\":\"\{told.0}\",\"percent\":\{told.1},\"error\":\"\"}")
      t.draw()
      assert_true(t.find(told.2) is Some(_), msg="\{at} \{told.2}")
      let (_, y, _, _) = t.rect_of("更新日志").unwrap()
      assert_eq(y, under, msg="\{at} \{told.2}")
    }
    t.tells_update("")
    @sfbase.update.available.set(None)
  }
}

///|
test "关于 where newer builds are not asked for (no source, as on iOS; no version, run from the sources): this build, no 检查更新" {
  let t = setting_tester(About, 390.0, platform=2)
  assert_true(t.find("still.fail mbui 0.1") is Some(_))
  assert_true(t.find("检查更新") is None)
  @sffixture.fixture_updates()
  @sfbase.update_version.val = 0
  t.draw()
  assert_true(t.find("检查更新") is None)
}

///|
test "关于's 检查更新 pressed: the update dialog over the page asks still.fail cloud now, then says what it answered in place of a toast; 确定 closes it" {
  for case in [(390.0, 2), (1280.0, 0)] {
    let (w, platform) = case
    let t = setting_tester(About, w, platform~)
    let asked : Array[(Result[Json, String]) -> Unit] = []
    @sfbase.update_version.val = 2
    @sfbase.set_update_source(Some({ check: fn(_, now, done) { if now { asked.push(done) } }, url: fn(f) { f } }))
    t.draw()
    t.tap_text("检查更新")
    t.draw()
    t.run_for(if platform == 2 { @kit.sheet_rest("sf-present") - t.time() } else { @kit.dialog_ms })
    let at = "\{w} platform \{platform}"
    assert_eq(asked.length(), 1, msg=at)
    assert_true(@sfbase.update_dialog_open(), msg=at)
    assert_true(t.find("正在检查最新版本") is Some(_), msg=at)
    assert_true(t.find("当前版本 0.1.2") is Some(_), msg=at)
    (asked[0])(Ok(Json::null()))
    t.draw()
    t.draw()
    assert_true(t.find("已是最新版本") is Some(_), msg=at)
    assert_eq(app.toast.get(), "", msg=at)
    assert_true(app.nav.top() == Setting(About), msg=at)
    t.click(Button, label="确定")
    t.draw()
    assert_true(!@sfbase.update_dialog_open(), msg=at)
    @sfbase.update_reset()
  }
}

///|
test "the update dialog where still.fail cloud could not be asked: why, 重试 asks again" {
  let t = setting_tester(About, 1280.0)
  let asked : Array[(Result[Json, String]) -> Unit] = []
  @sfbase.update_version.val = 2
  @sfbase.set_update_source(Some({ check: fn(_, now, done) { if now { asked.push(done) } }, url: fn(f) { f } }))
  t.draw()
  t.tap_text("检查更新")
  t.draw()
  t.run_for(@kit.dialog_ms)
  (asked[0])(Err("无法获取最新版本：offline"))
  t.draw()
  t.draw()
  assert_true(t.find("检查更新失败") is Some(_))
  assert_true(t.find("无法获取最新版本：offline") is Some(_))
  t.click(Button, label="重试")
  t.draw()
  assert_eq(asked.length(), 2)
  assert_true(t.find("正在检查最新版本") is Some(_))
  @sfbase.update_reset()
}

///|
test "更新日志, at each width and with either hand: the build, a tab a part, each day's changes with their kinds, versions and what is not out yet" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Changelog, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("当前版本 0.1.1300") is Some(_), msg=at)
    assert_true(t.find("此 app") is Some(_), msg=at)
    assert_true(t.find("10 月 19 日") is Some(_), msg=at)
    assert_true(t.find("新增") is Some(_), msg=at)
    assert_true(t.find("0.1.1288") is Some(_), msg=at)
    assert_true(t.find("更新后可用") is Some(_), msg=at)
    // another part: none of its own yet
    t.tap_text("Station")
    t.draw()
    assert_true(t.find("暂无更新记录") is Some(_), msg=at)
  }
}

///|
/// The fixture with the changelog's first tab alone (as the core gives it where each part's would be the same).
fn changelog_one_tab(base : Source) -> Source {
  {
    ..base,
    topic: fn(name, params) {
      let v = (base.topic)(name, params)
      match v.value {
        Some(Object(o)) if name == "changelog" =>
          match o.get("tabs") {
            Some(Array([first, ..])) => {
              let one = o.copy()
              one["tabs"] = Json::array([first])
              { ..v, value: Some(Json::object(one)) }
            }
            _ => v
          }
        _ => v
      }
    },
  }
}

///|
test "更新日志 with one tab (the stable channel's, each part's the same), at each width and with either hand: its changes, no choice over them" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Changelog, w, platform~, over=changelog_one_tab)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("10 月 19 日") is Some(_), msg=at)
    assert_true(t.find("0.1.1288") is Some(_), msg=at)
    assert_true(t.find("此 app") is None, msg=at)
  }
}

///|
test "更新日志 on a phone: a change's kind on a label before its words, which wrap under it; the label one line high" {
  let t = setting_tester(Changelog, 390.0, platform=2)
  let words = "对话列表偶尔把同一行显示两次，滑到底再滑回来也不会消失"
  let labels = t.drawn_rects().filter(fn(r) { r.4 == @sf.theme().p.chip && (r.3 - 19.0).abs() < 0.001 })
  assert_true(labels.length() >= 1)
  let rs = t.run_rects(words)
  assert_true(rs.length() >= 2)
  // the words' second line starts where the label does
  assert_true(labels.any(fn(l) { (rs[1].0 - l.0).abs() < 0.001 }))
}
