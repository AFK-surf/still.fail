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
