// The app's updates (updates.mbt) over a source of made-up builds: Home's key when one brings something, the settings'
// version row, nothing asked with no source.

///|
fn release(news : Array[String]) -> Json {
  {
    "versionCode": 2,
    "versionName": "0.1.1",
    "file": "android/stillfail-2.apk",
    "sha256": "ab",
    "size": 1000,
    "news": Json::array(news.map(fn(n) { Json::string(n) })),
  }
}

///|
fn updates_tester(r : Json, asked : Array[String]) -> @ui.Tester {
  reset()
  let src = fixture("home")
  update_version.val = 1
  set_update_source(
    Some({
      check: fn(version, now, done) {
        asked.push("\{version} \{now}")
        done(Ok(r))
      },
      url: fn(file) { "https://example.test/releases/" + file },
    }),
  )
  @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
}

///|
test "a newer build that brings something: Home's download key; 关于's row offers it by its version" {
  let asked = []
  let t = updates_tester(release(["列表滑得更顺"]), asked)
  t.frame()
  assert_eq(asked, ["1 false"])
  assert_true(update.available is Some(_))
  assert_eq((update_stands().doing, update_stands().newer), ("", "0.1.1"))
  // (not idle yet: a spinner turns for ever (sf/icons.mbt), till mbui#25)
}

///|
test "none newer: the row offers to check, and asked now says 已是最新" {
  let asked = []
  let _ = updates_tester(Json::null(), asked)
  assert_eq((update_stands().doing, update_stands().newer), ("", ""))
  let said = []
  update_check(fixture("home"), true, done=fn(w) { said.push(w) })
  assert_eq(said, ["已是最新"])
}

///|
test "no source: nothing is asked" {
  reset()
  update_version.val = 1
  let said = []
  update_check(fixture("home"), true, done=fn(w) { said.push(w) })
  assert_eq(said.length(), 0)
}

///|
test "an update's download answered otherwise: its status in Updates.kt's words" {
  assert_eq(update_error("status 404"), "下载返回 404")
  assert_eq(update_error("incomplete"), "下载的文件不完整，请重试")
  assert_eq(update_error("no space"), "no space")
}

///|
test "the update key while an update comes, one look on every screen: its mark, how far a bar under it as wide as the mark, no words; how far not known, its piece sweeping; no press taken" {
  reset()
  let coming : Ref[Double?] = Ref(Some(0.42))
  let t = @ui.Tester::new(
    fn(c) { @sf.update_key(c, "k", 34.0, 20.0, "下载中 42%", "", coming.val, false, true) |> ignore },
    w=120.0,
    h=80.0,
  )
  t.run_for(@kit.progress_ms)
  let accent = @sf.theme().p.accent
  let bars = t.drawn_rects().filter(fn(r) { (r.3 - 3.0).abs() < 0.001 })
  // the track as wide as the mark (20), 42% of it filled in the accent
  assert_true(bars.any(fn(r) { (r.2 - 20.0).abs() < 0.001 && r.4 != accent }), msg="no track as wide as the mark")
  assert_true(bars.any(fn(r) { (r.2 - 8.4).abs() < 0.01 && r.4 == accent }), msg="no fill 42% of it")
  assert_true(t.find("42%") is None)
  assert_true(t.query(Button, label="下载中 42%").unwrap().disabled, msg="takes no press while it comes")
  // how far not known (asked again first, going on after the network came back, installed): a piece of it sweeping
  coming.val = None
  t.run_for(@kit.progress_ms)
  let bars = t.drawn_rects().filter(fn(r) { (r.3 - 3.0).abs() < 0.001 })
  assert_true(bars.any(fn(r) { (r.2 - 20.0).abs() < 0.001 && r.4 != accent }), msg="no track while not known")
  assert_true(bars.any(fn(r) { r.4 == accent && r.2 < 20.0 }), msg="no piece sweeping")
}
