// The app's updates (updates.mbt) over a source of made-up builds: a newer build handed to the host at once, nothing
// over Home while it comes, a card there only for what wants the person, the settings' version row, nothing asked with
// no source.

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
  assert_eq(update_stands().label, "下载 0.1.1")
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
  new_run()
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
fn update_key_marks(busy : Bool) -> (@ui.Tester, Array[String]) {
  new_run()
  let t = @ui.Tester::new(
    fn(c) { @sf.update_key(c, "k", 34.0, 20.0, "重启更新", "", busy) |> ignore },
    w=120.0,
    h=80.0,
  )
  t.run_for(@kit.progress_ms)
  (t, t.shape_boxes().filter(fn(b) { b.0.contains("icon/") }).map(fn(b) { b.0 }))
}

///|
test "the update key, a build here already waiting on its press: the update's mark (an arrow up in a ring), not download's" {
  let (_, marks) = update_key_marks(false)
  assert_true(marks.iter().any(fn(m) { m.contains("icon/update") }), msg="\{marks}")
  assert_true(!marks.iter().any(fn(m) { m.contains("icon/download") }), msg="\{marks}")
}

///|
test "the update key while the build goes in: its arrow going up as a station's does (no download's mark), no words, no press" {
  let (t, marks) = update_key_marks(true)
  assert_true(!marks.iter().any(fn(m) { m.contains("icon/download") }), msg="\{marks}")
  assert_true(t.find("重启更新") is None)
  assert_true(t.query(Button, label="重启更新").unwrap().disabled, msg="takes no press while it goes in")
}
