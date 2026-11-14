// 关于 and 更新日志 (about.mbt) alone, at each width, with a finger and with a mouse: laid out as the web's narrow app in
// a narrow box, as its desktop pages in a wide one; the update dialog the page opens over it.

///|
test "关于, at each width and with either hand: this build, 更新日志, the terms and the privacy policy; a narrow page's rows on cards, a wide one's under its sections' titles" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(About, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("still.fail 0.1") is Some(_), msg=at)
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
test "关于 names the build for its channel" {
  for product in ["still.fail", "youdid.wtf"] {
    let t = setting_tester(About, 390.0, platform=2, over=fn(s) {
      {
        ..s,
        topic_read: fn(name, params) {
          if name == "prefs" {
            { value: Some(Json::object({ "productName": Json::string(product) })), error: None, version: 1 }
          } else {
            s.topic(name, params).get().snapshot()
          }
        },
      }
    })
    assert_true(t.find(product + " 0.1") is Some(_), msg=product)
  }
}

///|
test "关于's 性能记录 where the device keeps one, at each width and with either hand: last, under 诊断; its note says where it is kept and how much; turned on and off, the host told at once; none where the device keeps none" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    // (a Tester's host keeps none, as Android's, a Mac's)
    assert_true(setting_tester(About, w, platform~).find("性能记录") is None, msg=at)
    // (one kept, as iOS's)
    let t = setting_tester(About, w, platform~, host=fn(t) { t.set_perf(0) })
    t.wheel(w / 2.0, 450.0, 5000.0)
    t.run_for(@ui.move_most_ms)
    t.draw()
    assert_true(t.find("性能记录") is Some(_), msg=at)
    assert_eq(t.find("诊断") is Some(_), laid_wide(w), msg=at)
    assert_true(t.find("每 5 秒把 CPU、各线程占用、发热等级和帧数记在本机 Documents/perf（现有 0 B），不会上传。") is Some(_), msg=at)
    // last: under the terms
    let (_, terms, _, _) = t.rect_of("服务条款").unwrap()
    let (_, perf, _, _) = t.rect_of("性能记录").unwrap()
    assert_true(perf > terms, msg=at)
    t.click(Switch, label="性能记录")
    assert_eq(t.perf_said().0, [true], msg=at)
    assert_eq(@hostapi.perf_state(), 1, msg=at)
    t.draw()
    t.click(Switch, label="性能记录")
    assert_eq(t.perf_said().0, [true, false], msg=at)
    assert_eq(@hostapi.perf_state(), 0, msg=at)
  }
}

///|
test "关于's version rows, at each width and with either hand: this build alone on its row; under it a row saying how the update stands by its own words (检查更新 a row of its own; 有新版本 …, 正在下载 …, 重启以更新到 …), the line under its words and the bar under them while it comes, the row as tall all the way it comes" {
  for case in page_cases {
    let (w, platform) = case
    // (newer builds asked for as the app starts: the page made once with them)
    let t = setting_tester(About, w, platform~, host=fn(_) { @sffixture.fixture_updates() })
    let at = "\{w} platform \{platform}"
    assert_true(t.query(Link, label="检查更新") is Some(_), msg=at)
    @sfbase.update.available.set(Some({ "versionCode": 2, "versionName": "0.1.1", "file": "android/stillfail-2.apk", "size": 23515867 }))
    // (its row makes its way in under 检查更新: looked at once there)
    t.run_for(@ui.move_most_ms)
    // known, not handed to the host yet: offered, a row of its own under 检查更新 (still there); waiting for Wi‑Fi,
    // said with its size
    assert_true(t.query(Link, label="有新版本 0.1.1") is Some(_), msg=at)
    let (_, cy, _, _) = t.query(Link, label="检查更新").unwrap().rect
    assert_true(t.query(Link, label="有新版本 0.1.1").unwrap().rect.1 > cy, msg=at)
    t.tells_update("{\"phase\":\"waiting\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-2.apk\"}")
    t.draw()
    assert_true(t.find("连接 Wi‑Fi 后自动下载 · 22.4 MB") is Some(_), msg=at)
    // pressed: still.fail cloud asked now (the newest), then downloaded now, on any network
    t.click(Link, label="有新版本 0.1.1")
    assert_eq(t.update_asked(), ["fetch stillfail-2.apk false", "fetch stillfail-2.apk true"], msg=at)
    // coming: how far under its words, nothing beside them, the row as tall each way (what is under it where it was)
    let mut under = -1.0
    for told in [(40, "40% · 22.4 MB"), (-1, "22.4 MB"), (70, "70% · 22.4 MB")] {
      t.tells_update("{\"phase\":\"downloading\",\"percent\":\{told.0},\"error\":\"\",\"file\":\"stillfail-2.apk\"}")
      t.draw()
      assert_true(t.query(Link, label="正在下载 0.1.1") is Some(_), msg="\{at} \{told.1}")
      let (_, ny, _, _) = t.rect_of(told.1).unwrap()
      let (_, uy, _, uh) = t.rect_of("正在下载 0.1.1").unwrap()
      assert_true(ny >= uy + uh, msg=at)
      assert_true(t.beside_faults().is_empty(), msg="\{at}: \{Repr(t.beside_faults())}")
      let (_, y, _, _) = t.rect_of("更新日志").unwrap()
      if under < 0.0 {
        under = y
      }
      assert_eq(y, under, msg="\{at} \{told.1}")
    }
    // ready, put in place by itself while away (Android's): said so; pressed, put in place now
    t.tells_update("{\"phase\":\"ready\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-2.apk\",\"away\":true}")
    t.draw()
    assert_true(t.find("0.1.1300 → 0.1.1 已下载，离开 still.fail 一段时间后自动安装") is Some(_), msg=at)
    t.click(Link, label="重启以更新到 0.1.1")
    assert_eq(
      t.update_asked(),
      ["fetch stillfail-2.apk false", "fetch stillfail-2.apk true", "fetch stillfail-2.apk false", "apply"],
      msg=at,
    )
    t.tells_update("")
    @sfbase.update.available.set(None)
  }
}

///|
test "关于's update row stays usable with the pointer over it as a download becomes ready between frames" {
  let t = setting_tester(About, 1280.0, platform=0, host=fn(_) { @sffixture.fixture_updates() })
  @sfbase.update.available.set(Some({ "versionCode": 2, "versionName": "0.1.1", "file": "android/stillfail-2.apk", "size": 23515867 }))
  t.draw()
  t.tells_update("{\"phase\":\"downloading\",\"percent\":40,\"error\":\"\",\"file\":\"stillfail-2.apk\"}")
  // (its row made its way in: the pointer put over it where it rests)
  t.run_for(@ui.move_most_ms)
  let (x, y, w, h) = t.query(Link, label="正在下载 0.1.1").unwrap().rect
  t.move_to(x + w / 2.0, y + h / 2.0)
  let now = t.time()
  t.frame_shown_at(now + 20.0, now + 36.0)
  t.tells_update("{\"phase\":\"ready\",\"percent\":-1,\"error\":\"\",\"file\":\"stillfail-2.apk\",\"away\":false}")
  t.draw()
  let now = t.time()
  t.frame_shown_at(now, now + 16.0)
  t.click(Link, label="重启以更新到 0.1.1")
  assert_true(t.update_asked().contains("apply"), msg="the update was handed to the host")
  @sfbase.update_reset()
}

///|
test "关于 where newer builds are not asked for (no source, as on iOS; no version, run from the sources): this build, no 检查更新" {
  let t = setting_tester(About, 390.0, platform=2)
  assert_true(t.find("still.fail 0.1") is Some(_))
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
    let asked : Array[(Result[Json, String]) -> Unit] = []
    // (newer builds asked for as the app starts: the page made once with them)
    let t = setting_tester(About, w, platform~, ready=fn() {
      @sfbase.update_version.val = 2
      @sfbase.set_update_source(Some({ check: fn(_, now, done) { if now { asked.push(done) } }, url: fn(f) { f } }))
    })
    t.tap_text("检查更新")
    t.draw()
    t.run_for(if platform == 2 { @sf.presented_rest() - t.time() } else { @kit.dialog_ms })
    let at = "\{w} platform \{platform}"
    assert_eq(asked.length(), 1, msg=at)
    assert_true(@sfbase.update_dialog_open(), msg=at)
    assert_true(t.find("正在检查最新版本") is Some(_), msg=at)
    assert_true(t.find("当前版本 0.1.2") is Some(_), msg=at)
    (asked[0])(Ok(Json::null()))
    t.draw()
    t.draw()
    assert_true(t.find("已是最新版本") is Some(_), msg=at)
    assert_eq(app.toast.get().words, "", msg=at)
    assert_true(app.nav.top() == Setting(About), msg=at)
    t.click(Button, label="确定")
    t.draw()
    assert_true(!@sfbase.update_dialog_open(), msg=at)
    @sfbase.update_reset()
  }
}

///|
test "the update dialog where still.fail cloud could not be asked: why, 重试 asks again" {
  let asked : Array[(Result[Json, String]) -> Unit] = []
  let t = setting_tester(About, 1280.0, ready=fn() {
    @sfbase.update_version.val = 2
    @sfbase.set_update_source(Some({ check: fn(_, now, done) { if now { asked.push(done) } }, url: fn(f) { f } }))
  })
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
/// This machine's station as its host says it: a service running as Willow (the fixture's ws1/st1), a release behind.
let about_local : String =
  #|{"data":"~/.stillfail","runner":"service","version":"0.1.1288","service":{"kind":"launchd","name":"fail.still.station"},"workspace":{"id":"ws1","station":"st1","name":"星火工作室","stationName":"Willow","removed":false}}

///|
/// Words drawn whole and exactly `words` (not a line they are part of: the app's own version names the same build).
fn about_drawn(t : @ui.Tester, words : String) -> Bool {
  t.words().iter().any(fn(w) { w.0 == words && w.5 > 0.5 })
}

///|
test "关于's 本机 Station, at each width and with either hand: where the app looks after the station here, under the app's version its row as its page's 软件与更新 has it (Station, its version, the newer release and 更新, which updates it, its 自动更新); none where the app looks after none" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let calls : Array[(String, Json)] = []
    let t = setting_tester(About, w, platform~, host=fn(h) { h.set_app_said("local_station", about_local) }, over=fn(base) {
      {
        ..base,
        call: fn(name, params, done) {
          calls.push((name, params))
          (base.call)(name, params, done)
        },
      }
    })
    // (a phone's app looks after no station: nothing of it, the host's word or not)
    if platform != 0 {
      assert_true(t.find("0.1.1288") is None, msg=at)
      assert_true(t.query(Button, label="更新") is None, msg=at)
      continue
    }
    // its section's title laid out wide alone
    assert_eq(t.find("本机 Station") is Some(_), laid_wide(w), msg=at)
    for words in ["Station", "0.1.1288", "0.1.1300"] {
      assert_true(about_drawn(t, words), msg="\{at}: \{words}")
    }
    assert_true(t.query(Switch, label="自动更新") is Some(_), msg=at)
    // under the app's own
    let (_, app, _, _) = t.rect_of("更新日志").unwrap()
    let (_, own, _, _) = t.rect_of("0.1.1288").unwrap()
    assert_true(own > app, msg=at)
    // (every rule the screen is held to: its block adds no fault)
    let faults = t.audit()
    assert_true(faults.is_empty(), msg=at + ": " + faults.join(" | "))
    t.click(Button, label="更新")
    t.frame()
    let asked = named_calls(calls, "software.update")
    assert_eq(asked.length(), 1, msg=at)
    assert_eq(text(Some(asked[0]), "station"), "ws1/st1", msg=at)
    assert_eq(text(Some(asked[0]), "id"), "station", msg=at)
  }
}

///|
test "关于's 本机 Station where the core has none of its software up: its version as the host says it; while it is away, that its update is seen once it is up; nothing to update it with" {
  // (in a workspace this account is not in)
  let t = setting_tester(About, 1280.0, host=fn(h) {
    h.set_app_said("local_station", (
      #|{"data":"~/.stillfail","runner":"service","version":"0.1.4600","workspace":{"id":"ws9","station":"st9","name":"别处","stationName":"Elm","removed":false}}
      ),
    )
  })
  assert_true(about_drawn(t, "Station 0.1.4600"))
  assert_true(t.query(Button, label="更新") is None)
  assert_true(t.find("station 离线") is None)
  // (its own, away)
  let t = setting_tester(About, 1280.0, mode="settings-station-away", host=fn(h) { h.set_app_said("local_station", about_local) })
  assert_true(about_drawn(t, "Station 0.1.1288"))
  assert_true(t.find("station 离线，连接后可查看更新") is Some(_))
  assert_true(t.query(Button, label="更新") is None)
  let faults = t.audit()
  assert_true(faults.is_empty(), msg=faults.join(" | "))
  // (none here: nothing of it)
  let t = setting_tester(About, 1280.0, host=fn(h) { h.set_app_said("local_station", "") })
  assert_true(t.find("本机 Station") is None)
  assert_true(t.find("Station") is None)
  // (one added while the page is open: its block once its host is read again, a few seconds on, as 本机 Station's page
  // reads it)
  t.set_app_said("local_station", about_local)
  t.run_for(@settings.local_read_ms + @ui.move_most_ms)
  assert_true(t.find("本机 Station") is Some(_))
  assert_true(about_drawn(t, "0.1.1300"))
  assert_true(t.query(Button, label="更新") is Some(_))
}

///|
/// (The sweeps' 关于 has no station here, its fake host saying none: this block's own rules held here, in both of the
/// app's languages.)
test "关于's 本机 Station in English, at each width and with either hand, up and away: every rule held" {
  for case in page_cases {
    let (w, platform) = case
    for mode in ["settings", "settings-station-away"] {
      let at = "\{w} platform \{platform} \{mode}"
      // (English as the device says it: what a test sets before its Tester is put back as the Tester starts)
      let t = setting_tester(About, w, platform~, mode~, env=[("MBUI_LOCALE", "en-US")], host=fn(h) {
        h.set_app_said("local_station", about_local)
      })
      assert_eq(t.find("0.1.1288") is Some(_), platform == 0, msg=at)
      assert_eq(t.find("This machine's station") is Some(_), platform == 0 && laid_wide(w), msg=at)
      let faults = t.audit()
      assert_true(faults.is_empty(), msg=at + ": " + faults.join(" | "))
    }
  }
  @sf.set_language(None)
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
    topic_read: fn(name, params) {
      let v = base.topic(name, params).get().snapshot()
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
  let rs = t.run_rects(words)
  assert_true(rs.length() >= 2)
  // (its label: on the words' first line, where that line begins (the second's start))
  let labels = t
    .drawn_rects()
    .filter(fn(r) { r.4 == @sf.theme().p.chip && r.1 < rs[0].1 + rs[0].3 && r.1 + r.3 > rs[0].1 && (r.0 - rs[1].0).abs() < 0.001 })
  assert_eq(labels.length(), 1, msg="\{Repr(t.drawn_rects().filter(fn(r) { r.4 == @sf.theme().p.chip }))} \{Repr(rs)}")
  // (19 high at words of 15: as the words are set now, in the theme they are drawn in)
  let size = @ui.style_words(@sf.body).size
  assert_true((labels[0].3 - size * 19.0 / 15.0).abs() < 0.001, msg="\{Repr(labels[0])} at \{size}")
}

///|
test "关于's 性能记录 turned on stays on: its first line written (the 分享记录 row under it), a while on, the host told once" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(About, w, platform~, host=fn(t) { t.set_perf(0) })
    let at = "\{w} platform \{platform}"
    t.wheel(w / 2.0, 450.0, 5000.0)
    t.run_for(@ui.move_most_ms)
    t.draw()
    let (x, y, sw, sh) = t.get(Switch, label="性能记录").rect
    t.touch(0, x + sw / 2.0, y + sh / 2.0)
    t.draw()
    t.touch(2, x + sw / 2.0, y + sh / 2.0)
    t.draw()
    assert_eq(t.perf_said().0, [true], msg=at)
    t.set_perf_size(666.0)
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("分享记录") is Some(_), msg=at)
    assert_true(t.get(Switch, label="性能记录").check is Some(On), msg=at)
    assert_eq(t.perf_said().0, [true], msg=at)
    assert_eq(@hostapi.perf_state(), 1, msg=at)
  }
}

///|
test "关于's 性能记录 where the host has no share sheet (Windows): the way to its folder always, the logs being there whether it is kept or not, its own note, no 分享记录 whatever it holds; pressed, the folder opened" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let t = setting_tester(About, w, platform~, host=fn(t) {
      t.set_perf(0)
      t.set_perf_opens(true)
    })
    t.wheel(w / 2.0, 450.0, 5000.0)
    t.run_for(@ui.move_most_ms)
    t.draw()
    assert_true(t.find("每 5 秒把 CPU、内存和帧数记在本机 Documents/perf（现有 0 B），不会上传。报错不论开没开都记在这个文件夹。") is Some(_), msg=at)
    t.set_perf_size(666.0)
    t.run_for(@ui.move_most_ms)
    t.draw()
    assert_true(t.find("分享记录") is None, msg=at)
    assert_eq(t.perf_opened(), 0, msg=at)
    t.click(Link, label="打开日志文件夹")
    assert_eq(t.perf_opened(), 1, msg=at)
    assert_eq(t.perf_said().0, [], msg=at)
  }
}

///|
test "自动更新 in 关于, on unless turned off: off, a newer build is said but downloaded only at the person's word; on again, the one known downloaded by itself" {
  let kept : Ref[Source?] = Ref(None)
  let newer : Json = { "versionCode": 3, "versionName": "0.1.3", "file": "android/stillfail-3.apk", "sha256": "ab", "size": 1000 }
  let t = setting_tester(
    About,
    390.0,
    platform=2,
    over=fn(s) {
      kept.val = Some(s)
      s
    },
    ready=fn() {
      @sfbase.update_version.val = 2
      @sfbase.set_update_source(Some({ check: fn(_, _, done) { done(Ok(newer)) }, url: fn(f) { f } }))
    },
  )
  let src = kept.val.unwrap()
  t.click(Switch, label="自动更新")
  t.frame()
  t.frame()
  assert_false(@sfbase.update_auto(src))
  @sfbase.update_check(src, false)
  assert_eq(t.update_asked(), [])
  assert_eq(@sfbase.update_stands().label, "有新版本 0.1.3")
  @sfbase.update_go(src)
  assert_eq(t.update_asked(), ["fetch stillfail-3.apk true"])
  // (the update's row come in meanwhile: pressed once all is at rest)
  t.run_for(@ui.move_most_ms)
  t.click(Switch, label="自动更新")
  t.frame()
  t.frame()
  assert_true(@sfbase.update_auto(src))
  assert_eq(t.update_asked(), ["fetch stillfail-3.apk true", "fetch stillfail-3.apk false"])
  @sfbase.update_check(src, false)
  assert_eq(t.update_asked().length(), 3)
  @sfbase.update_reset()
}
