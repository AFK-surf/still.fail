// Adding a profile on the desktop (sfpages new_profile.mbt, a wide page), a secret's page, a place's first,
// over the whole app and the settings' fixture (a profile's own page: src/sfpages accounts_wbtest.mbt).

///|
test "wide: the profile list's rows say an account's name and allowance, its tier its page's" {
  let t = wide_tester([], mode="settings")
  app.nav.replace(Place("profiles"))
  t.draw()
  // (the plan beside the name cut the name short in the narrowest sidebar; where it can be used and who uses it are the
  // account's page's too: the user, 2026-11-14)
  let side = t.text_runs().filter(fn(r) { r.x1 < 300.0 })
  assert_true(side.iter().any(fn(r) { r.text == "Claude 主账号" }), msg="\{Repr(side.map(fn(r) { r.text }))}")
  assert_true(side.iter().all(fn(r) { r.text != "Ultra" && !r.text.contains("可用") }), msg="\{Repr(side.map(fn(r) { r.text }))}")
}

///|
/// The desk's page wheeled down until `words` shows on it (above the window's foot).
fn desk_shown(t : @ui.Tester, words : String) -> Unit {
  t.move_to(800.0, 400.0)
  for _ in 0..<12 {
    match t.find(words) {
      Some((_, y)) if y < 760.0 => break
      _ => t.wheel(800.0, 400.0, 300.0)
    }
  }
}

///|
test "wide: Anthropic authorization in either browser waits for confirmation" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings-new-profile-login-station")
  @settings.fixture_page("settings-new-profile-login-station") |> ignore
  t.draw()
  app.nav.push(Setting(@settings.Route::NewProfile("ws1/st1")))
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="打开授权页面")
  sheet_rested(t, "sf-present")
  assert_true(t.find("打开 Claude 授权页面？") is Some(_))
  assert_true(t.opened().is_empty())
  t.back()
  sheet_rested(t, "sf-present")
  t.click(Button, label="在 Willow 的浏览器中打开")
  sheet_rested(t, "sf-present")
  assert_true(t.find("打开 Claude 授权页面？") is Some(_))
  assert_true(named(calls, "login.browser").is_empty())
  t.tap_text("继续打开")
  assert_eq(named(calls, "login.browser").length(), 1)
}

///|
test "station browser button sits beside 打开授权页面 and wraps cleanly at default and 1.3x words" {
  for mode in ["settings-profile-login-station", "settings-new-profile-login-station"] {
    for lang in ["zh", "en"] {
      let label = if lang == "zh" { "在 Willow 的浏览器中打开" } else { "Open in Willow's browser" }
      for win in corner_windows {
        let t = screen_in(mode, win, lang, motion_judged=false)
        assert_true(t.query(Button, label~) is Some(_), msg="\{win.0}-\{lang} \{mode}")
        assert_eq(t.squeeze_faults() + t.words_over_now() + t.fixed_outgrown(), [], msg="\{win.0}-\{lang} \{mode}")
      }
      guard corner_windows.search_by(w => w.0 == "phone") is Some(i) else { fail("no phone window") }
      let t_large = screen_in(mode, corner_windows[i], lang, font_scale=words_large_scale, motion_judged=false)
      assert_true(t_large.query(Button, label~) is Some(_), msg="phone-\{lang}-1.3 \{mode}")
      assert_eq(t_large.squeeze_faults() + t_large.words_over_now() + t_large.fixed_outgrown(), [], msg="phone-\{lang}-1.3 \{mode}")
    }
  }
}

///|
test "wide: adding a profile picks its provider from the core's groups, the machine's own login offered first" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings")
  t.draw()
  app.nav.push(Setting(@settings.Route::NewProfile("ws1/st1")))
  t.run_for(@ui.move_most_ms)
  // the core's step: its title and hint, its groups and their providers
  assert_true(t.find("选择服务商") is Some(_))
  assert_true(t.find("模型厂商") is Some(_) && t.find("中转站") is Some(_))
  assert_true(t.find("OpenRouter") is Some(_))
  // Willow's own Codex login, used as it is
  assert_true(t.find("使用此账号") is Some(_), msg="the machine's login offered")
  // a provider picked: told to the core
  match t.find("DeepSeek") {
    Some((x, y)) => t.tap(x, y)
    None => @halt.saying("no DeepSeek")
  }
  t.draw()
  assert_true(
    calls.iter().any(fn(m) { m.name == "profile.flow.edit" && text(field(Some(m.params), "input"), "provider") == "deepseek" }),
    msg="the provider told to the core",
  )
}

///|
test "wide: the station's Hermes profile can be selected from its custom variables" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings-new-profile-hermes")
  t.draw()
  app.nav.push(Setting(@settings.Route::NewProfile("ws1/st1")))
  t.run_for(@ui.move_most_ms)
  desk_shown(t, "Hermes Agent")
  match t.find("Hermes Agent") {
    Some((x, y)) => t.tap(x, y)
    None => @halt.saying("no Hermes Agent")
  }
  t.draw()
  assert_true(
    calls.iter().any(fn(m) { m.name == "profile.flow.edit" && text(field(Some(m.params), "input"), "provider") == "env-hermes" }),
    msg="the selected Hermes profile told to the core",
  )
}

///|
test "wide: a secret's page says what it is, how agents may get it and when they did, its content masked until opened" {
  let t = wide_tester([], mode="settings")
  t.draw()
  app.nav.push(Setting(@settings.Route::VaultItem("v1", "it1")))
  t.run_for(@ui.move_most_ms)
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
  t.run_for(@ui.move_most_ms)
  // its scene and its one thing to do (the sidebar's 添加 station too)
  assert_true(t.find_last("添加 station") is Some(_))
}

///|
/// The profiles' place opened on 大屏 by touch (a tablet's window), a profile's page in its pane as it opens: the pane's
/// coming reads the layout for its size before any frame, and the page's blocks, made as that layout comes to them,
/// each read theirs. Begun inside it, that second layout left what the first laid out unplaced (mbui's
/// Tree::measured_now, #5245, whose own ways in were a phone's): the page's head and its sections' titles drawn where
/// and as big as whatever had their nodes before, a title 18 wide a letter a line. With a mouse a change is laid out as
/// it ends, for what is under the pointer, so the same steps there read no layout still to be done. Every frame is held
/// placed as laid out (Tester::hold_placed); said here of the first as well.
test "wide, by touch: the profiles' place opens on a page placed as it is laid out" {
  let t = wide_tester([], mode="settings-profile-fable", w=1100.0, h=700.0, platform=2)
  @settings.fixture_page("settings-profile-fable") |> ignore
  app.nav.replace(Place("profiles"))
  t.draw()
  assert_eq(t.placed_faults(), [])
  // (its sections' titles each across the page's column, none in a box of a few points)
  for words in ["额度", "可使用的 station"] {
    let wide = t.words().filter(fn(w) { w.0 == words }).map(fn(w) { w.3 })
    assert_true(wide.length() == 1 && wide[0] > 200.0, msg="\{words}: \{Repr(wide)} wide")
  }
}

///|
test "wide: a machine's login not made a profile yet shows its allowance in the profiles' sidebar" {
  // (the fixture's place-profiles-offer, as sffix opens it; the Tester opens the place itself)
  let t = wide_tester([], mode="settings")
  @settings.fixture_page("settings-profiles-offer") |> ignore
  app.nav.replace(Place("profiles"))
  t.draw()
  // Willow's own Codex login, last in the sidebar: its week's capsule under its row as a profile's row has it
  let side = fn() { t.text_runs().filter(fn(r) { r.x0 < 300.0 }) }
  let offered = side().filter(fn(r) { r.text == "使用此账号" })
  assert_eq(offered.length(), 1, msg="the machine's login offered: \{Repr(side().map(fn(r) { r.text }))}")
  let under = side().filter(fn(r) { r.top >= offered[0].bottom }).map(fn(r) { r.text })
  for words in ["5H", "62%", "W", "19%"] {
    assert_true(under.contains(words), msg="\{words} under the offered login: \{Repr(under)}")
  }
  assert_eq(t.squeeze_faults(), [])
}

///|
/// How late the made-up core answers each call and every subscription as another station is pressed on the add page
/// (ms): at once, a frame late, and on to well past the 300 ms nothing may look like loading in.
let station_press_lates : Array[Double] = [0.0, 16.0, 120.0, 250.0, 400.0, 700.0]

///|
/// The add page's hint (the core's `hint`, its lead under its title), the same for each station in the fixture.
let station_press_hint : String = "订阅和 API key 都在这里添加"

///|
/// How long after the press the page is at rest, over a core answering `ms` late: its answer, the page come, and a
/// motion's most after it, twice.
fn station_press_rest_ms(ms : Double) -> Double {
  ms * 4.0 + @ui.move_most_ms * 2.0
}

///|
/// The add page on Willow (ws1/st1) in screen `s`, three stations online, over the settings' fixture whose core answers
/// each call and every subscription as late as `pace` says when it is asked (the page opened at once, the test's own
/// setup), as a device's host draws it (check_looks off), at rest: what it was asked told to `heard`, the calls made to
/// `calls`.
fn station_press_tester(s : Screen, pace : Ref[Double], heard : Array[String], calls : Array[(String, Json)]) -> @ui.Tester {
  new_run()
  let base = fixture_app("settings-new-profile-stations")
  let counted : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push((name, params))
      (base.call)(name, params, done)
    },
  }
  let src = round_trip_again(round_trip_by(counted, fn() { pace.val }), 0.0, heard=fn(h) { heard.push(h) }, late=fn(_, _) {
    pace.val
  })
  if !(app.nav.top() is Setting(NewProfile("ws1/st1"))) {
    app.nav.push(Setting(@settings.Route::NewProfile("ws1/st1")))
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=s.w, h=s.h, platform=s.platform)
  t.check_looks(false)
  t.draw()
  t.run_for(@ui.move_most_ms + 1000.0)
  t.ways_set_out() |> ignore
  t
}

///|
/// Station `name` shown chosen on the page's choice now.
fn station_chosen(t : @ui.Tester, name : String) -> Bool {
  t.query(Radio, label=name, checked=On) is Some(_)
}

///|
/// Another station pressed on the add page (大屏 with a mouse, 小屏 by touch), the page opened over a core answering at
/// once and the press over one answering 0 to 700 ms late: from the press till the page is at rest, in every frame as a
/// host draws it (each frame held steady too: sizes_steady.mbt), nothing sets out after the press's own
/// moment (no hint squeezed shut and opened, no section going up and down), the hint drawn (Willow's page's or Maple's,
/// never neither), no frame on the providers' bones, the choice on Maple from the press; at rest the page is Maple's,
/// its draft opened once and its flow asked once and held (what the press asked handed to it: sfbase's open_answered).
test "the add page's station choice opens the other station's page whole, the page as it was meanwhile" {
  for s in [daily_large, daily_small] {
    for ms in station_press_lates {
      let at = "\{s.name}, \{ms} ms"
      let heard : Array[String] = []
      let calls : Array[(String, Json)] = []
      let pace = Ref(0.0)
      let t = station_press_tester(s, pace, heard, calls)
      pace.val = ms
      assert_true(station_chosen(t, "Willow"), msg="\{at}: Willow chosen at first")
      assert_true(t.find(station_press_hint) is Some(_), msg="\{at}: the hint at first")
      let bones_before = t.bones_drawn()
      let maple = match t.query(Radio, label="Maple") {
        Some(r) => r
        None => @halt.saying("\{at}: no Maple to press")
      }
      let from = t.time()
      t.tap(maple.rect.0 + maple.rect.2 / 2.0, maple.rect.1 + maple.rect.3 / 2.0)
      let faults : Array[String] = []
      let ways : Array[String] = []
      let mut came = -1.0
      let frames = (station_press_rest_ms(ms) / @ui.frame_period_default).ceil().to_int()
      for i in 0..=frames {
        if i > 0 {
          t.run_for(@ui.frame_period_default)
        }
        let now = t.time() - from
        for w in t.ways_set_out() {
          if w.at > from + 0.5 {
            ways.push("\{w.kind} +\{(w.at - from).round()} ms \{w.made} \{w.part}")
          }
        }
        let waiting = app.nav.top() is Setting(NewProfile("ws1/st1"))
        if !waiting && came < 0.0 {
          came = now
        }
        if t.find(station_press_hint) is None {
          faults.push("+\{now.round()} ms: no hint drawn (\{if waiting { "waiting" } else { "Maple's page" }})")
        }
        if t.bones_drawn() > bones_before {
          faults.push("+\{now.round()} ms: \{t.bones_drawn()} bones drawn, \{bones_before} before the press")
        }
        if !station_chosen(t, "Maple") {
          faults.push("+\{now.round()} ms: Maple not shown chosen")
        }
      }
      println("STATION_PRESS \{at}: Maple's page at +\{came.round()} ms, ways after the press \{Repr(ways)}")
      assert_eq(faults, [], msg="\{at}: every frame from the press")
      assert_eq(ways, [], msg="\{at}: ways set out after the press")
      assert_true(app.nav.top() is Setting(NewProfile("ws1/st2")), msg="\{at}: Maple's page at rest")
      let opened = calls.filter(fn(c) { c.0 == "profile.flow.open" && text(Some(c.1), "station") == "ws1/st2" })
      assert_eq(opened.length(), 1, msg="\{at}: Maple's draft opened: \{Repr(opened.map(fn(c) { c.1.stringify() }))}")
      let form = text(Some(opened[0].1), "form")
      assert_eq(
        asked_held(heard, "profileFlow", { "station": Json::string("ws1/st2"), "form": Json::string(form) }),
        (1, 0),
        msg="\{at}: Maple's flow asked and let go",
      )
    }
  }
}
