// A profile's page (accounts.mbt, the web's Accounts.tsx AccountView) alone over the settings' fixture: Studio's
// (ws1/st1) Claude subscription and its API key, wide; the step right after a profile is added and a profile's models,
// one page each in every frame, at each width with either hand, over ChatGPT 团队.

///|
test "a profile's page, wide: who it is and whether it works, then its allowance, what it spent, who uses it, how it runs, sharing" {
  let t = setting_tester(Profile("ws1/st1", "cc"), 1280.0)
  // its head: its name, what it is (the core's words), its last check
  assert_true(t.find("Claude 主账号") is Some(_))
  assert_true(t.find("订阅账号") is Some(_), msg="what it is")
  assert_true(t.find("订阅有效") is Some(_), msg="its check in a line")
  // what is left of its allowance, a dial each
  assert_true(t.find("额度") is Some(_))
  assert_true(t.find("5 小时") is Some(_) && t.find("本周") is Some(_), msg="its windows")
  // who uses it, how it runs, whom it is shared with
  scrolled_to(t, 1280.0, "使用它的连接")
  assert_true(t.find("使用它的连接") is Some(_))
  scrolled_to(t, 1280.0, "默认 Fast")
  assert_true(t.find("默认 Fast") is Some(_))
  scrolled_to(t, 1280.0, "分享给其他 station")
  assert_true(t.find("分享给其他 station") is Some(_), msg="sharing")
}

///|
test "a key's profile's page, wide: its key masked, a new one asked for from its row" {
  let t = setting_tester(Profile("ws1/st1", "k2"), 1280.0)
  assert_true(t.find("备用 key") is Some(_))
  scrolled_to(t, 1280.0, "sk-…a41f")
  assert_true(t.find("sk-…a41f") is Some(_), msg="its key masked")
  // (the row's own: its trouble's 更换 key may be drawn above, out of sight)
  tap_words(t, "更换")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("新的 API key") is Some(_), msg="a new key asked for")
}

///|
test "a profile's page, wide: a profile one of the station's lists no more says so" {
  let t = setting_tester(Profile("ws1/st1", "gone"), 1280.0)
  assert_true(t.find("找不到 ID 为 gone 的 Profile") is Some(_))
}

///|
test "a profile just added, at each width and with either hand: its models to choose; 跳过 goes on to its page in this one's place" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(PickModels("ws1/st1", "cx"), w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("选择模型") is Some(_), msg=at)
    assert_true(t.find("ChatGPT 团队") is Some(_), msg=at)
    // its list, by the core's series
    assert_true(t.find("GPT-6-MINI") is Some(_), msg=at)
    assert_true(t.find("完成") is Some(_), msg=at)
    tap_words(t, "跳过")
    t.run_for(@ui.move_most_ms)
    // (in this one's place: none of it left under its page)
    assert_true(app.nav.top() == Setting(Profile("ws1/st1", "cx")), msg=at)
    assert_false(app.nav.pages().contains(Setting(PickModels("ws1/st1", "cx"))), msg=at)
  }
}

///|
test "a profile's models, at each width and with either hand: how many are on, each to tick" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(ProfileModels("ws1/st1", "cx"), w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("已选 1 项") is Some(_), msg=at)
    assert_true(t.find("GPT-6-MINI") is Some(_), msg=at)
    assert_true(t.find("GPT-5.5") is Some(_), msg=at)
    // read again, at the title's end
    assert_true(t.find("刷新模型") is Some(_), msg=at)
  }
}

///|
test "a profile's models, wide with a mouse: the series side by side, a model's id right under its name" {
  let t = setting_tester(ProfileModels("ws1/st1", "cx"), 1280.0)
  // the third of GPT-6 and of GPT-5.5 on one line, the second series beside the first
  match (t.find("GPT-6-NANO"), t.find("GPT-5.5-CODEX")) {
    (Some((x6, y6)), Some((x55, y55))) => {
      assert_true((y6 - y55).abs() < 1.0, msg="side by side")
      assert_true(x55 > x6, msg="the newer first")
    }
    _ => abort("no GPT-6-NANO or GPT-5.5-CODEX")
  }
  // its id under the pointer, under its own words (not under the middle of the page)
  let (nx, ny) = t.find("O9-MINI").unwrap()
  t.move(nx, ny)
  t.run_for(@sf.tip_delay_ms + 200.0)
  match t.find("o9-mini") {
    Some((tx, ty)) => {
      assert_true((tx - nx).abs() < 40.0, msg="under its name: \{tx} for \{nx}")
      assert_true(ty > ny, msg="under it")
    }
    None => abort("no tip")
  }
  t.leave()
  t.run_for(@kit.tooltip_delay_ms)
}

// A profile's quota reset and its models (Accounts.tsx QuotaSection, ModelPool) over ChatGPT 团队: a reset used once
// asked, its models chosen in place (ModelChecklist): a model named by hand, a filter over the many.

///|
test "a profile's quota, a narrow page with a mouse: 重置额度 asks first, then uses one of the resets left" {
  let t = setting_tester(Profile("ws1/st1", "cx"), 390.0)
  scrolled_to(t, 390.0, "还可重置 2 次")
  t.tap_text("重置额度")
  t.frame()
  assert_true(@sf.presenting(), msg="asked first")
  assert_true(t.find("重置额度？") is Some(_))
  assert_true(t.find("将使用「ChatGPT 团队」的 1 次额度重置，剩余 2 次") is Some(_))
  // (with a mouse: the web's confirm, come in)
  t.run_for(@kit.presence_in_ms)
  t.tap_text("使用一次重置")
  t.frame()
  t.frame()
  assert_true(t.find("还可重置 1 次") is Some(_))
}

///|
test "a profile's models, a narrow page with a mouse: chosen in place, one named by hand is added, the filter leaves what has its words" {
  let t = setting_tester(Profile("ws1/st1", "cx"), 390.0)
  // on its page, 模型's 选择模型 (how many of how many on) opens the whole list there
  scrolled_to(t, 390.0, "选择模型（1 / 12）")
  t.tap_text("选择模型（1 / 12）")
  t.draw()
  assert_true(t.find("收起") is Some(_))
  scrolled_to(t, 390.0, "筛选模型")
  assert_true(t.find("O9-MINI") is Some(_))
  // a name typed, then 添加
  scrolled_to(t, 390.0, "按名称添加模型")
  t.tap_text("按名称添加模型")
  t.type_text("my-model")
  t.frame()
  // (添加 alone: the field's placeholder has the word too)
  tap_words(t, "添加")
  t.frame()
  t.frame()
  scrolled_to(t, 390.0, "MY-MODEL")
  assert_true(t.find("MY-MODEL") is Some(_), msg="the model named, among the rest")
  // a filter: 全选 / 取消 say they are of what it leaves
  scrolled_to(t, 390.0, "筛选模型")
  t.tap_text("筛选模型")
  t.type_text("codex")
  t.frame()
  assert_true(t.find("GPT-6-CODEX") is Some(_))
  assert_true(t.find("O9-MINI") is None)
  assert_true(t.find("全选筛选结果") is Some(_))
  assert_true(t.find("取消选择筛选结果") is Some(_))
}
