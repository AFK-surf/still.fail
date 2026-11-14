// The app's updates (updates.mbt) over a source of made-up builds: a newer build handed to the host at once, nothing
// over Home while it comes, a card there only for what wants the person, the settings' version row, nothing asked with
// no source; a delta from this build handed to the host beside it, its size said as what comes.

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
  new_run()
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
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
}

///|
test "a newer build: handed to the host at once to be made ready, nothing over Home while it comes; 关于's row offers it by its version" {
  let asked = []
  let t = updates_tester(release(["列表滑得更顺"]), asked)
  t.frame()
  assert_eq(asked, ["1 false"])
  assert_true(update.available.get() is Some(_))
  // (as asked at the start: it may wait for a network that is not metered)
  assert_eq(t.update_asked(), ["fetch stillfail-2.apk false"])
  assert_eq(update_stands().label, "有新版本 0.1.1")
  t.tells_update("{\"phase\":\"downloading\",\"percent\":40,\"error\":\"\",\"file\":\"stillfail-2.apk\"}")
  t.run_for(@ui.move_most_ms)
  assert_true(update_button_at(t, "传输") is None, msg="the build coming shown over Home")
  assert_true(t.find("40%") is None)
  assert_eq((update_stands().label, update_stands().note), ("正在下载 0.1.1", "40% · 1000 B"))
  // ready, put in place by itself while away: still nothing over Home
  t.tells_update("{\"phase\":\"ready\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-2.apk\",\"away\":true}")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("允许安装更新") is None)
  assert_eq(update_stands().ready, "0.1.1")
}

///|
test "a newer build with a delta from this build: the delta handed to the host beside it, its size said as what comes; one without, none" {
  let sha = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
  let with_delta : Json = {
    "versionCode": 2,
    "versionName": "0.1.1",
    "file": "android/stillfail-2.apk",
    "sha256": "ab",
    "size": 1000000,
    "news": ["列表滑得更顺"],
    "delta": {
      "file": "android/stillfail-2.apk.from-1.delta",
      "sha256": sha,
      "size": 2048,
      "makesSha256": "ab",
      "makesSize": 1000000,
    },
  }
  let t = updates_tester(with_delta, [])
  t.frame()
  assert_eq(t.update_asked(), [
    "fetch stillfail-2.apk false delta {\"url\":\"https://example.test/releases/android/stillfail-2.apk.from-1.delta\",\"sha256\":\"\{sha}\",\"size\":2048,\"makes_sha256\":\"ab\",\"makes_size\":1000000}",
  ])
  assert_eq(update_stands().note, "2 KB")
  t.tells_update("{\"phase\":\"waiting\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-2.apk\"}")
  assert_eq(update_stands().note, @sf.t("android-misc.updates.waitWifi", args=[("size", "2 KB")]))
  t.tells_update("{\"phase\":\"downloading\",\"percent\":40,\"error\":\"\",\"file\":\"stillfail-2.apk\"}")
  assert_eq(update_stands().note, "40% · 2 KB")
  // (the core's answer with no delta: null, as it sends it)
  let without = release([])
  if without is Object(o) {
    o["delta"] = Json::null()
  }
  let t = updates_tester(without, [])
  t.frame()
  assert_eq(t.update_asked(), ["fetch stillfail-2.apk false"])
  assert_eq(update_stands().note, "1000 B")
}

///|
/// The button said as `label` (none: not shown).
fn update_button_at(t : @ui.Tester, label : String) -> (Double, Double, Double, Double)? {
  for s in t.semantics() {
    if s.label == label && s.role == @ui.Role::Button && !s.hidden {
      return Some(s.rect)
    }
  }
  None
}

///|
test "the leave to install apps wanted: a card over Home says so; pressed, the host asked to put the build in place (its page for the leave first)" {
  let t = updates_tester(release(["列表滑得更顺"]), [])
  t.frame()
  t.tells_update("{\"phase\":\"allow\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-2.apk\",\"away\":true}")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("still.fail 需要你允许它安装应用，之后会自动更新") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  t.tap_text("允许安装更新")
  // (still.fail cloud asked now first: the same build, handed again, taken by the host as asked already)
  assert_eq(t.update_asked(), ["fetch stillfail-2.apk false", "fetch stillfail-2.apk false", "apply"])
  // given: gone
  t.tells_update("{\"phase\":\"ready\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-2.apk\",\"away\":true}")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("允许安装更新") is None)
}

///|
test "a newer build found during a download is fetched when the host finishes the previous one" {
  let t = updates_tester(release([]), [])
  t.frame()
  t.tells_update("{\"phase\":\"downloading\",\"percent\":40,\"error\":\"\",\"file\":\"stillfail-2.apk\"}")
  let newer : Json = {
    "versionCode": 3,
    "versionName": "0.1.2",
    "file": "android/stillfail-3.apk",
    "sha256": "cd",
    "size": 1000,
    "news": [],
  }
  set_update_source(Some({ check: fn(_, _, done) { done(Ok(newer)) }, url: fn(file) { file } }))
  update_check(fixture("home"), false)
  // The host is still busy: the old download stays visible until the newer one can start.
  assert_eq(update_stands().label, "正在下载 0.1.1")
  assert_eq(t.update_asked(), ["fetch stillfail-2.apk false"])
  t.tells_update("{\"phase\":\"ready\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-2.apk\"}")
  t.run_for(@ui.move_most_ms)
  assert_eq(t.update_asked(), ["fetch stillfail-2.apk false", "fetch stillfail-3.apk false"])
}

///|
test "several releases found during one download: fetch the newest even if an older check answers last" {
  let t = updates_tester(release([]), [])
  t.frame()
  t.tells_update("{\"phase\":\"downloading\",\"percent\":40,\"error\":\"\",\"file\":\"stillfail-2.apk\"}")
  let version3 : Json = { "versionCode": 3, "versionName": "0.1.2", "file": "android/stillfail-3.apk", "sha256": "cd", "size": 1000 }
  let version4 : Json = { "versionCode": 4, "versionName": "0.1.3", "file": "android/stillfail-4.apk", "sha256": "ef", "size": 1000 }
  let answer = Ref(version3)
  set_update_source(Some({ check: fn(_, _, done) { done(Ok(answer.val)) }, url: fn(file) { file } }))
  update_check(fixture("home"), false)
  answer.val = version4
  update_check(fixture("home"), false)
  answer.val = version3
  update_check(fixture("home"), false)
  t.tells_update("{\"phase\":\"failed\",\"percent\":-1,\"error\":\"incomplete\",\"file\":\"stillfail-2.apk\"}")
  t.run_for(@ui.move_most_ms)
  assert_eq(t.update_asked(), ["fetch stillfail-2.apk false", "fetch stillfail-4.apk false"])
  assert_eq(update_stands().label, "有新版本 0.1.3")
}

///|
test "a build that failed is handed to the host again as the app is shown again (its check), and at the person's word now" {
  let asked = []
  let t = updates_tester(release(["列表滑得更顺"]), asked)
  t.frame()
  t.tells_update("{\"phase\":\"failed\",\"percent\":-1,\"error\":\"status 404\",\"file\":\"stillfail-2.apk\"}")
  assert_eq((update_stands().label, update_stands().note), ("重试更新到 0.1.1", "下载返回 404"))
  update_check(fixture("home"), false)
  update_go(fixture("home"))
  assert_eq(t.update_asked(), [
    "fetch stillfail-2.apk false", "fetch stillfail-2.apk false", "fetch stillfail-2.apk false", "fetch stillfail-2.apk true",
  ])
}

///|
test "a download becoming ready while its check is in flight never turns that press into a restart" {
  let t = updates_tester(release([]), [])
  t.frame()
  let asked : Array[(Result[Json, String]) -> Unit] = []
  set_update_source(Some({ check: fn(_, _, done) { asked.push(done) }, url: fn(file) { file } }))
  t.tells_update("{\"phase\":\"waiting\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-2.apk\"}")
  update_go(fixture("home"))
  assert_eq(asked.length(), 1)
  t.tells_update("{\"phase\":\"ready\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-2.apk\",\"away\":false}")
  (asked[0])(Ok(release([])))
  assert_false(t.update_asked().contains("apply"))
  assert_eq(update_stands().ready, "0.1.1")
}

///|
test "a restart check finding a newer build downloads it instead of restarting the older one" {
  let t = updates_tester(release([]), [])
  t.frame()
  let asked : Array[(Result[Json, String]) -> Unit] = []
  set_update_source(Some({ check: fn(_, _, done) { asked.push(done) }, url: fn(file) { file } }))
  t.tells_update("{\"phase\":\"ready\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-2.apk\",\"away\":false}")
  update_go(fixture("home"))
  let newer : Json = { "versionCode": 3, "versionName": "0.1.2", "file": "android/stillfail-3.apk", "size": 1000 }
  (asked[0])(Ok(newer))
  assert_false(t.update_asked().contains("apply"))
  assert_true(t.update_asked().contains("fetch stillfail-3.apk true"))
  assert_eq(update_stands().label, "有新版本 0.1.2")
}

///|
test "a restart check cannot apply a different release even if it reuses the same file name" {
  let t = updates_tester(release([]), [])
  t.frame()
  let asked : Array[(Result[Json, String]) -> Unit] = []
  set_update_source(Some({ check: fn(_, _, done) { asked.push(done) }, url: fn(file) { file } }))
  t.tells_update("{\"phase\":\"ready\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-2.apk\",\"away\":false}")
  update_go(fixture("home"))
  let newer : Json = { "versionCode": 3, "versionName": "0.1.2", "file": "android/stillfail-2.apk", "sha256": "cd", "size": 1000 }
  (asked[0])(Ok(newer))
  assert_false(t.update_asked().contains("apply"))
}

///|
test "none newer: the row offers to check, and asked now says 已是最新" {
  let asked = []
  let _ = updates_tester(Json::null(), asked)
  assert_eq((update_stands().label, update_stands().ready), ("检查更新", ""))
  let said = []
  update_check(fixture("home"), true, done=fn(w) { said.push(w) })
  assert_eq(said, ["已是最新"])
}

///|
///|
test "no source: nothing is asked; asked now, it says why" {
  fresh_app()
  update_version.val = 1
  let said = []
  update_check(fixture("home"), false, done=fn(w) { said.push(w) })
  assert_eq(said.length(), 0)
  update_check(fixture("home"), true, done=fn(w) { said.push(w) })
  assert_eq(said, ["检查更新失败：开发版不检查更新"])
  assert_eq(update.said.get(), UpdateSaid::CouldNot("开发版不检查更新"))
  assert_false(update_asks())
}

///|
test "still.fail cloud's feed asked with the release keys the app's environment adds (STILLFAIL_RELEASE_KEYS), none without" {
  new_run()
  let base = fixture("home")
  let asked : Array[String] = []
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "app.update" {
        asked.push(params.stringify())
        done(Ok(Json::null()))
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let updates = cloud_updates(src, "win/mbui", "https://example.test")
  let _ = @ui.Tester::new(fn(_) {  }, env=[("STILLFAIL_RELEASE_KEYS", " k1=, k2= ,")])
  (updates.check)(5, false, fn(_) {  })
  let _ = @ui.Tester::new(fn(_) {  })
  (updates.check)(5, true, fn(_) {  })
  assert_eq(asked, [
    "{\"platform\":\"win/mbui\",\"versionCode\":5,\"now\":false,\"keys\":[\"k1=\",\"k2=\"]}",
    "{\"platform\":\"win/mbui\",\"versionCode\":5,\"now\":true}",
  ])
}

///|
test "an update's download answered otherwise: its status in Updates.kt's words" {
  assert_eq(update_error("status 404"), "下载返回 404")
  assert_eq(update_error("incomplete"), "下载的文件不完整，请重试")
  assert_eq(update_error("no space"), "no space")
}

///|
/// The update key drawn at 34, its mark 20, `busy` or not: the names of the icons it draws.
fn update_key_marks(busy : Bool, restart? : Bool = false, offered? : Bool = false) -> (@ui.Tester, Array[String]) {
  new_run()
  let t = @ui.Tester::new(
    fn(c) { @sf.update_key(c, "k", 34.0, 20.0, "重启更新", "", busy, restart~, offered~) |> ignore },
    w=120.0,
    h=80.0,
  )
  t.run_for(@kit.progress_ms)
  (t, t.shape_boxes().filter(fn(b) { b.0.contains("icon/") }).map(fn(b) { b.0 }))
}

///|
test "the update key keeps its drawing and colours only the outer ring when ready to restart" {
  let (_, marks) = update_key_marks(false, restart=true)
  let p = @sf.theme().p
  assert_eq(marks, ["sf/icon/update/[0]/20/\{p.green}", "sf/icon/update/[1, 2]/20/\{p.text}"])
  let (_, ordinary) = update_key_marks(false)
  assert_eq(ordinary, ["sf/icon/update/[0]/20/\{p.text}", "sf/icon/update/[1, 2]/20/\{p.text}"])
  let (_, offered) = update_key_marks(false, offered=true)
  assert_eq(offered, ["sf/icon/download/20/\{p.text}"])
}

///|
test "the old-view update key does not turn a held download press into a restart" {
  new_run()
  let restart = @signals.signal(false, same=fn(a, b) { a == b })
  let presses = Ref(0)
  let t = @ui.Tester::new(fn(c) {
    @sf.update_key(c, "k", 34.0, 20.0, "更新", "", false, offered=!restart.get(), restart=restart.get(), on_press=fn() {
      presses.val += 1
    })
  }, w=120.0, h=80.0)
  t.frame()
  let (x, y, w, h) = t.query(Button, label="更新").unwrap().rect
  t.touch(0, x + w / 2.0, y + h / 2.0)
  restart.set(true)
  t.draw()
  t.touch(2, x + w / 2.0, y + h / 2.0)
  assert_eq(presses.val, 0)
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq(presses.val, 1)
}

///|
test "the update key while the build goes in: its arrow going up as a station's does (no download's mark), no words, no press" {
  let (t, marks) = update_key_marks(true)
  assert_true(!marks.iter().any(fn(m) { m.contains("icon/download") }), msg="\{Repr(marks)}")
  assert_true(t.find("重启更新") is None)
  assert_true(t.query(Button, label="重启更新").unwrap().disabled, msg="takes no press while it goes in")
}

///|
test "left open, a newer build asked for again each hour: a window never shown again does not stay on its build" {
  let asked = []
  let t = updates_tester(Json::null(), asked)
  t.frame()
  assert_eq(asked, ["1 false"])
  // (each hour in one jump, a frame at its end: run_for drew Home's spokes at every 100 ms step on the way, 90 000
  // frames and 100-146 s of CI for two and a half hours (2026-11-09); the ask is a function of the moment)
  t.frame(ms=@sfbase.update_again_ms / 2.0)
  assert_eq(asked, ["1 false"])
  t.frame(ms=@sfbase.update_again_ms / 2.0 + 1000.0)
  assert_eq(asked, ["1 false", "1 false"])
  t.frame(ms=@sfbase.update_again_ms)
  assert_eq(asked, ["1 false", "1 false", "1 false"])
}

///|
test "told a release may be out: a newer build asked for again at once, not as the hour's check" {
  let asked = []
  new_run()
  let told = @signals.signal(3)
  let base = fixture("home")
  let src : @sfbase.Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "releases" {
        { value: Some({ "told": Json::number(told.get().to_double()) }), error: None, version: 1 }
      } else {
        (base.topic_read)(name, params)
      }
    },
  }
  update_version.val = 1
  set_update_source(
    Some({
      check: fn(version, now, done) {
        asked.push("\{version} \{now}")
        done(Ok(Json::null()))
      },
      url: fn(file) { "https://example.test/releases/" + file },
    }),
  )
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.frame()
  // (what the core had said before the app heard it: nothing more than the start's check)
  assert_eq(asked, ["1 false"])
  told.set(4)
  t.frame()
  assert_eq(asked, ["1 false", "1 false"])
  told.set(5)
  t.frame()
  t.frame()
  assert_eq(asked, ["1 false", "1 false", "1 false"])
}
