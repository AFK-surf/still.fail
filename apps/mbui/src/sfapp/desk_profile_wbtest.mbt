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
test "wide: a profile's page says who it is and whether it works, then its allowance, what it spent, sharing, its models, how it runs, who uses it" {
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
  // shared, for its home's other workspaces, fast, its models
  assert_true(t.find("分享给其他 station") is Some(_), msg="sharing")
  desk_shown(t, "默认 Fast")
  assert_true(t.find("默认 Fast") is Some(_))
  desk_shown(t, "使用它的连接")
  assert_true(t.find("使用它的连接") is Some(_))
}

///|
test "wide: a key's profile shows its key masked, replaced in place" {
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
  t.draw()
  assert_true(t.find("新的 API key") is Some(_), msg="a new key typed in its place")
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
