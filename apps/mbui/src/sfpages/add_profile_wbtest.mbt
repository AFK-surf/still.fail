// A new profile (add_profile.mbt) alone, at each width, with a finger and with a mouse: the core's step, its providers
// in their groups, the machine's own login offered first; a provider picked told to the core.

///|
test "adding a profile, at each width and with either hand: its provider picked from the core's groups, the machine's own login offered first" {
  for case in page_cases {
    let (w, platform) = case
    let calls : Array[(String, Json)] = []
    let t = setting_tester(NewProfile("ws1/st1"), w, platform~, over=fn(s) {
      { ..s, call: fn(name, params, done) { calls.push((name, params)); (s.call)(name, params, done) } }
    })
    let at = "\{w} platform \{platform}"
    // the core's step: its title, its groups and their providers
    assert_true(t.find("选择服务商") is Some(_), msg=at)
    assert_true(t.find("模型厂商") is Some(_) && t.find("中转站") is Some(_), msg=at)
    assert_true(t.find("OpenRouter") is Some(_), msg=at)
    // Studio's own Codex login, used as it is
    assert_true(t.find("使用此账号") is Some(_), msg="\{at}: the machine's login offered")
    assert_eq(t.squeeze_faults(), [], msg=at)
    // a provider picked: told to the core
    scrolled_to(t, w, "DeepSeek")
    t.tap_text("DeepSeek")
    t.draw()
    assert_true(
      calls.iter().any(fn(m) { m.0 == "profile.flow.edit" && text(field(Some(m.1), "input"), "provider") == "deepseek" }),
      msg="\{at}: the provider told to the core",
    )
  }
}

///|
test "adding a profile: the station's Hermes profile can be picked from its custom variables" {
  let calls : Array[(String, Json)] = []
  let t = setting_tester(NewProfile("ws1/st1"), 1280.0, mode="settings-new-profile-hermes", over=fn(s) {
    { ..s, call: fn(name, params, done) { calls.push((name, params)); (s.call)(name, params, done) } }
  })
  scrolled_to(t, 1280.0, "Hermes Agent")
  t.tap_text("Hermes Agent")
  t.draw()
  assert_true(
    calls.iter().any(fn(m) { m.0 == "profile.flow.edit" && text(field(Some(m.1), "input"), "provider") == "env-hermes" }),
    msg="the picked Hermes profile told to the core",
  )
}
