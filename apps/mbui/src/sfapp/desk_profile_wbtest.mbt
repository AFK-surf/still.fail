// A profile's page on the desktop (sfdesk accounts.mbt, the web's Accounts.tsx AccountView) over the settings'
// fixture: Studio's (ws1/st1) Claude subscription, and its API key.

///|
/// The desk's page wheeled down until `words` shows on it (above the window's foot).
fn desk_shown(t : @ui.Tester, words : String) -> Unit {
  t.move(800.0, 400.0)
  for _ in 0..<12 {
    match t.find(words) {
      Some((_, y)) if y < 760.0 => break
      _ => t.wheel(800.0, 400.0, 300.0)
    }
  }
}

///|
test "wide: a profile's page says who it is and whether it works, then its allowance, what it spent, who uses it, how it runs, sharing" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings")
  t.draw()
  app.nav.push(Setting(@settings.Route::Profile("ws1/st1", "cc")))
  t.run_for(@ui.nav_push_ms)
  // its head: its name, what it is (the core's words), its last check
  assert_true(t.find("Claude 主账号") is Some(_))
  assert_true(t.find("订阅账号") is Some(_), msg="what it is")
  assert_true(t.find("订阅有效") is Some(_), msg="its check in a line")
  // what is left of its allowance, a dial each
  assert_true(t.find("额度") is Some(_))
  assert_true(t.find("5 小时") is Some(_) && t.find("本周") is Some(_), msg="its windows")
  // who uses it, how it runs, whom it is shared with
  desk_shown(t, "使用它的连接")
  assert_true(t.find("使用它的连接") is Some(_))
  desk_shown(t, "默认 Fast")
  assert_true(t.find("默认 Fast") is Some(_))
  desk_shown(t, "分享给其他 station")
  assert_true(t.find("分享给其他 station") is Some(_), msg="sharing")
}

///|
test "wide: a key's profile shows its key masked, a new one asked for from its row" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings")
  t.draw()
  app.nav.push(Setting(@settings.Route::Profile("ws1/st1", "k2")))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("备用 key") is Some(_))
  desk_shown(t, "sk-…a41f")
  assert_true(t.find("sk-…a41f") is Some(_), msg="its key masked")
  match t.find("更换") {
    Some((x, y)) => t.tap(x, y)
    None => abort("no 更换")
  }
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("新的 API key") is Some(_), msg="a new key asked for")
}

///|
test "wide: a profile one of the station's lists no more says so" {
  let t = wide_tester([], mode="settings")
  t.draw()
  app.nav.push(Setting(@settings.Route::Profile("ws1/st1", "gone")))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("找不到 ID 为 gone 的 Profile") is Some(_))
}

///|
test "wide: adding a profile picks its provider from the core's groups, the machine's own login offered first" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings")
  t.draw()
  app.nav.push(Setting(@settings.Route::NewProfile("ws1/st1")))
  t.run_for(@ui.nav_push_ms)
  // the core's step: its title and hint, its groups and their providers
  assert_true(t.find("选择服务商") is Some(_))
  assert_true(t.find("模型厂商") is Some(_) && t.find("中转站") is Some(_))
  assert_true(t.find("OpenRouter") is Some(_))
  // Studio's own Codex login, used as it is
  assert_true(t.find("使用此账号") is Some(_), msg="the machine's login offered")
  // a provider picked: told to the core
  match t.find("DeepSeek") {
    Some((x, y)) => t.tap(x, y)
    None => abort("no DeepSeek")
  }
  t.draw()
  assert_true(
    calls.iter().any(fn(m) { m.name == "profile.flow.edit" && text(field(Some(m.params), "input"), "provider") == "deepseek" }),
    msg="the provider told to the core",
  )
}

///|
test "wide: a new profile's models chosen on a page of their own, then on to its page" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings")
  t.draw()
  app.nav.push(Setting(@settings.Route::PickModels("ws1/st1", "cc")))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("Opus 5.5") is Some(_) && t.find("Haiku 5") is Some(_), msg="its whole list to tick")
  match t.find("完成") {
    Some((x, y)) => t.tap(x, y)
    None => abort("no 完成")
  }
  t.run_for(@ui.nav_push_ms)
  assert_true(app.nav.top() is Setting(@settings.Route::Profile("ws1/st1", "cc")), msg="on to its page")
}

///|
test "wide: a secret's page says what it is, how agents may get it and when they did, its content masked until opened" {
  let t = wide_tester([], mode="settings")
  t.draw()
  app.nav.push(Setting(@settings.Route::VaultItem("v1", "it1")))
  t.run_for(@ui.nav_push_ms)
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
test "wide: a skill's memory page says what it is and when it is read, its pages picked by their pills" {
  let t = wide_tester([], mode="settings")
  t.draw()
  app.nav.push(Setting(@settings.Route::MemoryDoc("ws1/st1", "发布流程", 0)))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("项目记忆 · 读取时机") is Some(_), msg="what it is, the core's")
  assert_true(t.find("发布新版本时") is Some(_))
  // its SKILL.md first, then the file picked
  assert_true(t.find("总览") is Some(_) && t.find("checklist") is Some(_))
  match t.find("checklist") {
    Some((x, y)) => t.tap(x, y)
    None => abort("no checklist")
  }
  t.draw()
  assert_true(t.find("签名") is Some(_), msg="the file's text")
}

///|
test "wide: the Station place with none in the workspace is the first to add, not a phone's page" {
  let t = wide_tester([], mode="settings-first-station")
  t.draw()
  app.nav.replace(Place("stations"))
  t.run_for(@ui.nav_push_ms)
  // its scene and its one thing to do (the sidebar's 添加 station too)
  assert_true(t.find_last("添加 station") is Some(_))
}
